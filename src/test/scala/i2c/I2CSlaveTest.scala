// See README.md for license details.

package i2cslave

import java.io.File

import chisel3._
import chisel3.util._
import org.scalatest._
import chiseltest._
import chiseltest.internal.VerilatorBackendAnnotation
import chiseltest.experimental.TestOptionBuilder._

class I2CSlaveTestRegister(addressWidth: Int) extends Module {
  val io = IO(new I2CSlaveRegIO(addressWidth))

  val mem = RegInit(VecInit(Range(0, 256).map(x => x.U(8.W))))
  val response = RegInit(false.B)
  io.response := response
  val read_data = RegInit(0.U(8.W))
  io.read_data := read_data
  
  response := false.B
  when(io.request) {
    response := true.B
    when( io.is_write ) {
      mem(io.address) := io.write_data
    } otherwise {
      read_data := mem(io.address)
    }
  }

}

class I2CSlaveTestSystem(addressWidth: Int, filterDepth: Int, i2cAddress: Int) extends Module {
  val dut = Module(new I2CSlave(addressWidth, filterDepth, i2cAddress))
  val testReg = Module(new I2CSlaveTestRegister(addressWidth))
  val io = IO(new I2CIO)
  io <> dut.io.i2c
  testReg.io <> dut.io.reg_if
}

class I2CSlaveUnitTester(system: I2CSlaveTestSystem, i2cClockBase: Int)  {
  def i2cStart = {
    system.io.scl_i.poke(true.B)
    system.io.sda_i.poke(true.B)
    system.clock.step(i2cClockBase)
    system.io.sda_i.poke(false.B)
    system.clock.step(i2cClockBase)
  }
  def i2cStop = {
    system.io.scl_i.poke(true.B)
    system.io.sda_i.poke(false.B)
    system.clock.step(i2cClockBase)
    system.io.sda_i.poke(true.B)
    system.clock.step(i2cClockBase)
  }
  def i2cRead(ack: Boolean): Int = {
    var data:Int = 0
    system.io.scl_i.poke(true.B)
    for(i <- 0 until 8) {
      system.io.scl_i.poke(false.B)
      system.clock.step(i2cClockBase*2)
      system.io.scl_i.poke(true.B)
      system.clock.step(i2cClockBase)
      data = (data << 1) | (if( system.io.sda_o.peek.litToBoolean ) 1 else 0)
      system.clock.step(i2cClockBase)
    }
    system.io.scl_i.poke(false.B)
    system.clock.step(i2cClockBase)
    system.io.sda_i.poke((!ack).B)
    system.clock.step(i2cClockBase)
    system.io.scl_i.poke(true.B)
    system.clock.step(i2cClockBase*2)
    system.io.scl_i.poke(false.B)
    system.clock.step(i2cClockBase*2)
    data
  }
  def i2cWrite(value: Int): Boolean = {
    var data: Int = value
    system.io.scl_i.poke(true.B)
    for(i <- 0 until 8) {
      system.io.scl_i.poke(false.B)
      system.io.sda_i.poke(((data & 0x80) != 0).B)
      data = data << 1
      system.clock.step(i2cClockBase*2)
      system.io.scl_i.poke(true.B)
      system.clock.step(i2cClockBase*2)
    }
    system.io.scl_i.poke(false.B)
    system.io.sda_i.poke(true.B)
    system.clock.step(i2cClockBase*2)
    system.io.scl_i.poke(true.B)
    system.clock.step(i2cClockBase)
    val ack = !system.io.sda_o.peek.litToBoolean
    system.clock.step(i2cClockBase)
    system.io.scl_i.poke(false.B)
    system.clock.step(i2cClockBase*2)
    ack
  }

  def i2cRegisterRead(device: Int, address: Int): Option[Int]  = {
    var value: Option[Int] = None
    i2cStart
    if( i2cWrite((device << 1) | 0) ) {
      if( i2cWrite(address) ) {
        i2cStart
        if( i2cWrite((device << 1) | 1) ) {
          value = Some(i2cRead(false))
        }
      }
    }
    i2cStop
    value
  }

  def i2cRegisterWrite(device: Int, address: Int, value: Int): Boolean = {
    var success = false
    i2cStart
    if( i2cWrite((device << 1) | 0) ) {
      if( i2cWrite(address) ) {
        if( i2cWrite(value) ) {
          success = true
        }
      }
    }
    i2cStop
    success
  }
}

class I2CSlaveTester extends FlatSpec with ChiselScalatestTester with Matchers {
  val dutName = "I2CSlave"
  val i2cClockBase = 5
  val i2cDeviceAddress = 0x48
  behavior of dutName

  it should "Read must be successful" in {
    test(new I2CSlaveTestSystem(8, 3, i2cDeviceAddress)).withAnnotations(Seq(VerilatorBackendAnnotation)) { c => new I2CSlaveUnitTester(c, i2cClockBase) {
      c.clock.setTimeout(1000)
      for( i:Int <- 0 to 255) {
        val result = i2cRegisterRead(i2cDeviceAddress, i)
        assert(result.isDefined, f"reg #$i: read failed")
        if( result.isDefined ) {
          assert(result.get == i, f"reg #$i: data mismatch, expected=$i, actual=${result.get}")
        }
      }
    }}
  } 
  it should "Write must be successful" in {
    test(new I2CSlaveTestSystem(8, 3, i2cDeviceAddress)).withAnnotations(Seq(VerilatorBackendAnnotation)) { c => new I2CSlaveUnitTester(c, i2cClockBase) {
      c.clock.setTimeout(1000)
      for( i:Int <- 0 to 255) {
        var nv = 0
        var ii = i
        for( j <- 0 to 7 ) {
          nv = (nv << 1) | (ii & 1)
          ii = ii >> 1
        }
        val success = i2cRegisterWrite(i2cDeviceAddress, i, nv)
        assert(success, f"reg #$i: write failed")
        val result = i2cRegisterRead(i2cDeviceAddress, i)
        assert(result.isDefined, f"reg #$i: read failed")
        if( result.isDefined ) {
          assert(result.get == nv, f"reg #$i: data mismatch, expected=$nv, actual=${result.get}")
        }
      }
    }}
  } 
  it should "Recover from malformed transaction must success" in {
    test(new I2CSlaveTestSystem(8, 3, i2cDeviceAddress)).withAnnotations(Seq(VerilatorBackendAnnotation)) { c => new I2CSlaveUnitTester(c, i2cClockBase) {
      c.clock.setTimeout(1000)
      i2cStart
      i2cStop
      val result = i2cRegisterRead(i2cDeviceAddress, 0xde)
      assert(result.isDefined, "read failed after start-stop malformed transaction")
    }}
  }
}
