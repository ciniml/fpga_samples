// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

// See README.md for license details.

package spi

import java.io.File

import chisel3._
import chisel3.util._
import org.scalatest._
import chiseltest._

class SPIMasterTestSystem(halfClockDivider: Int = 10, dataBits: Int = 8) extends Module {
  val dut = Module(new SPIMaster(halfClockDivider, dataBits))
  val DataType = UInt(dataBits.W)
  val io = IO(new Bundle{
    val tx = Flipped(Irrevocable(DataType))
    val rx = Irrevocable(DataType)
  })

  val shiftReg = RegInit(0.U(dataBits.W))
  val sck = RegInit(false.B)
  val mosiBit = RegInit(false.B)
  when( dut.io.spi.cs ) {
    shiftReg := 0.U
    sck := dut.io.spi.sck
  } .otherwise {
    sck := dut.io.spi.sck
    when( !sck && dut.io.spi.sck ) {  // Rising edge
      mosiBit := dut.io.spi.mosi
    } .elsewhen( sck && !dut.io.spi.sck ) { // Falling edge
      shiftReg := Cat(shiftReg(dataBits-2, 0), mosiBit)
    }
  }

  dut.io.spi.miso := shiftReg(7)

  dut.io.tx <> io.tx
  dut.io.rx <> io.rx
}

class SPIMasterTester extends FlatSpec with ChiselScalatestTester with Matchers {
  val dutName = "SPIMaster"
  behavior of dutName

  it should "Loopback" in {
    test(new SPIMasterTestSystem()).withAnnotations(Seq(VerilatorBackendAnnotation)) { c => { 
      c.io.tx.initSource().setSourceClock(c.clock)
      c.io.rx.initSink().setSinkClock(c.clock)
      c.clock.setTimeout(2000)
      fork {
        for( i:Int <- 0 to 255 ) {
          c.io.tx.enqueue(i.U)
        }
        c.io.tx.enqueue(128.U)  // ignored
        c.clock.step(200)
        for( i:Int <- 0 to 255 ) {
          c.io.tx.enqueue(i.U)
        }
        c.io.tx.enqueue(0.U)
      } .fork {
        c.io.rx.expectDequeue(0.U)
        for( i:Int <- 0 to 255 ) {
          c.io.rx.expectDequeue(i.U)
        }
        c.io.rx.expectDequeue(0.U)
        for( i:Int <- 0 to 255 ) {
          c.io.rx.expectDequeue(i.U)
        }
      } .join
    }
  }}
}
