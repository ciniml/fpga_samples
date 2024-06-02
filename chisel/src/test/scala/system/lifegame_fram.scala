// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

// See README.md for license details.

package system

import java.io.File

import chisel3._
import chisel3.util._
import org.scalatest._
import chiseltest._


class LifeGameFramTestSystem() extends Module {
  val dut = Module(new LifeGameFram(new LifeGameFramConfig(8, 8, 10, 10, 1, 10)))
  val io = IO(new Bundle{
    val data = Output(UInt(8.W))
    val row = Output(UInt(8.W))
  })

  dut.clock := this.clock
  dut.reset := this.reset
  dut.initialize := false.B
  io.data := dut.data
  io.row := dut.row

  val DeviceId = "x047f4803".U  
  val WREN  = "b00000110".U
  val WRDI  = "b00000100".U
  val RDSR  = "b00000101".U
  val WRSR  = "b00000001".U
  val READ  = "b00000011".U
  val WRITE = "b00000010".U
  val FSTRD = "b00001011".U
  val RDID  = "b10011111".U
  val SLEEP = "b10111001".U

  object State extends ChiselEnum {
      val Command, ReadId, ReadStart, Read, WriteStart, Write = Value
  }
  val state = RegInit(State.Command)
  val byteCounter = RegInit(0.U(4.W))

  val shiftReg = RegInit(0.U(8.W))
  val sck = RegInit(false.B)
  val mosiBit = RegInit(false.B)
  val counter = RegInit(0.U(4.W))
  val memory = RegInit(VecInit(Seq(0.U(8.W), 0.U(8.W), 0.U(8.W), 0.U(8.W), 0.U(8.W), 0.U(8.W), 0.U(8.W), 0.U(8.W), 0x01.U(8.W))))
  val address = RegInit(0.U(24.W))

  dut.spi_so := shiftReg(7)
  when( dut.spi_cs_n ) {
    shiftReg := 0.U
    sck := dut.spi_sck
    counter := 0.U
    state := State.Command
  } .otherwise {
    sck := dut.spi_sck
    when( !sck && dut.spi_sck ) {  // Rising edge
      mosiBit := dut.spi_si
    } .elsewhen( sck && !dut.spi_sck ) { // Falling edge
      val data = Cat(shiftReg(8-2, 0), mosiBit)
      shiftReg := data
      counter := Mux(counter < 7.U, counter + 1.U, 0.U)
      when(counter === 7.U) {
        switch(state) {
          is(State.Command) {
            printf(p"[TEST] command=${Hexadecimal(data)} ")
            when(data === RDID) {
              printf(p"RDID\n")
              state := State.ReadId
              byteCounter := 0.U
              shiftReg := DeviceId(31, 24)
            } .elsewhen(data === READ) {
              printf(p"READ\n")
              state := State.ReadStart
              byteCounter := 0.U
            } .elsewhen(data === WREN) {
              printf(p"WREN\n")
              state := State.Command
            } .elsewhen(data === WRITE) {
              printf(p"WRITE\n")
              state := State.WriteStart
              byteCounter := 0.U
            } .otherwise {
              printf(p"Unknown\n")
            }
          }
          is(State.ReadId) {
            shiftReg := MuxLookup(byteCounter, 0.U)(Seq(
              0.U -> DeviceId(23, 16), 
              1.U -> DeviceId(15, 8),
              2.U -> DeviceId(7, 0),
            ))
            byteCounter := byteCounter + 1.U
            when(byteCounter === 3.U) {
              state := State.Command
            }
          }
          is(State.ReadStart) {
            val nextAddress = ((address << 8) | data)(23, 0)
            address := nextAddress
            byteCounter := byteCounter + 1.U
            when(byteCounter === 2.U) {
              val nextData = memory(nextAddress)
              printf(p"[TEST] Read address=${Hexadecimal(nextAddress)} data=${Hexadecimal(nextData)}\n")
              state := State.Read
              shiftReg := nextData
              address := (nextAddress + 1.U)
            }
          }
          is(State.Read) {
            val nextData = memory(address)
            printf(p"[TEST] Read address=${Hexadecimal(address)} data=${Hexadecimal(nextData)}\n")
            shiftReg := nextData
            address := address + 1.U
          }
          is(State.WriteStart) {
            val nextAddress = ((address << 8) | data)(23, 0)
            address := nextAddress
            byteCounter := byteCounter + 1.U
            when(byteCounter === 2.U) {
              state := State.Write
              shiftReg := 0.U
            }
          }
          is(State.Write) {
            printf(p"[TEST] Write address=${Hexadecimal(address)} data=${Hexadecimal(data)}\n")
            shiftReg := 0.U
            memory(address) := data
            address := address + 1.U
          }
        }
      }
    }
  }
}

class LifeGameFramTester extends FlatSpec with ChiselScalatestTester with Matchers {
  val dutName = "LifeGameFram"
  behavior of dutName

  it should "Run" in {
    test(new LifeGameFramTestSystem()).withAnnotations(Seq(VerilatorBackendAnnotation)) { c => { 
      c.clock.setTimeout(20000)
      c.clock.step(10000)
    }
  }}
}
