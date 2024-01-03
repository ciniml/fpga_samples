// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package video

import chiseltest._
import chisel3._
import chisel3.util._
import scala.util.control.Breaks
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers 

import java.io.FileInputStream
import scala.collection.mutable
import _root_.util.AsyncFIFO
import axi._
import chisel3.experimental.BundleLiterals._
import chisel3.experimental.ChiselEnum

class FrameBufferReaderTestSystem(scaling: Int, pixelBits: Int = 24) extends Module {
  val params = new VideoParams(pixelBits, 2, 20, 4, 3, 5, 24, 2, 1)
  val maxBurstCount = 6
  val dut = Module(
    new FrameBufferReader(
      params.pixelBits,
      params.pixelsH,
      params.pixelsV,
      32,
      maxBurstCount
    )
  )

  val io = IO(new Bundle {
    val video = Irrevocable(new VideoSignal(params.pixelBits))
    val forceTrigger = Input(Bool())
  })

  val triggerCounter = RegInit(4.U)
  when(triggerCounter > 0.U) {
    triggerCounter := triggerCounter - 1.U
  }
  dut.io.trigger := triggerCounter > 0.U || io.forceTrigger

  val values: Seq[UInt] = params.pixelBits match {
    case 16 => (0 to (params.framePixels - 1)).flatMap(v => (0 to 1).map(x => BigInt(v*2 + x) & 0xff)).grouped(4).map(x => (x(0) | (x(1) << 8) | (x(2) << 16) | (x(3) << 24)).U).toSeq
    case 24 => (0 to (params.framePixels - 1)).flatMap(v => (0 to 2).map(x => BigInt(v*3 + x) & 0xff)).grouped(4).map(x => (x(0) | (x(1) << 8) | (x(2) << 16) | (x(3) << 24)).U).toSeq
    case n => { assert(false, f"pixelBits ${n} not supported"); Seq() }
  }
  val memoryAddressBits = log2Ceil(params.frameBytes * 2)
  val memory = Module(new AXI4Memory(memoryAddressBits, 32, AXI4ReadOnly, maxBurstCount))
  val rom = Module(new RomReader(memoryAddressBits, 32, values, 0))
  
  dut.io.config.startX := 0.U
  dut.io.config.startY := 0.U
  dut.io.config.scaleX := scaling.U
  dut.io.config.scaleY := scaling.U
  dut.io.config.pixelsV := (params.pixelsV/scaling).U
  dut.io.config.pixelsH := (params.pixelsH/scaling).U

  dut.io.mem <> memory.io.axi4
  rom.io.reader <> memory.io.reader.get

  dut.io.data <> io.video
}

class FrameBufferReaderTester
    extends AnyFlatSpec
    with ChiselScalatestTester
    with Matchers {
  val dutName = "FrameBufferReader"
  behavior of dutName

  it should "simple" in {
    test(new FrameBufferReaderTestSystem(1)).withAnnotations(Seq(VerilatorBackendAnnotation)) { c =>
      val width = c.params.pixelsH
      val height = c.params.pixelsV
      c.clock.setTimeout(width * height * 3 )
      c.io.video.initSink().setSinkClock(c.clock)
      val signalType = chiselTypeOf(c.io.video.bits)
      (0 to (width * height * 2) - 1).foreach(i => {
        val pixelAddress = i % (width * height)
        val startOfFrame = pixelAddress == 0
        c.io.forceTrigger.poke(startOfFrame.B)

        val pixelValueBase = BigInt(pixelAddress * 3)
        val pixelValue0 = (pixelValueBase + 0) & 0xff
        val pixelValue1 = (pixelValueBase + 1) & 0xff
        val pixelValue2 = (pixelValueBase + 2) & 0xff
        val pixelValue = pixelValue0 | (pixelValue1 << 8) | (pixelValue2 << 16) 
        c.io.video.expectDequeue(
          signalType.Lit(
            _.pixelData -> pixelValue.U,
            _.startOfFrame -> startOfFrame.B,
            _.endOfLine -> (i % width == width - 1).B
          )
        )
      })

      c.io.video.expectInvalid()
    }
  }
  it should "double" in {
    test(new FrameBufferReaderTestSystem(2)).withAnnotations(Seq(VerilatorBackendAnnotation)) { c =>
      val width = c.params.pixelsH
      val height = c.params.pixelsV
      c.clock.setTimeout(width * height * 3 )
      c.io.video.initSink().setSinkClock(c.clock)
      val signalType = chiselTypeOf(c.io.video.bits)
      (0 to 1).foreach(frame => {
        (0 to (height / 2) - 1).foreach(y => {
          (0 to 1).foreach(yy => {
            (0 to (width / 2) - 1).foreach(x => {
              (0 to 1).foreach(xx => {
                val pixelAddress = y * width + x
                val startOfFrame = pixelAddress == 0 && yy == 0 && xx == 0
                c.io.forceTrigger.poke(startOfFrame.B)

                val pixelValueBase = BigInt(pixelAddress * 3)
                val pixelValue0 = (pixelValueBase + 0) & 0xff
                val pixelValue1 = (pixelValueBase + 1) & 0xff
                val pixelValue2 = (pixelValueBase + 2) & 0xff
                val pixelValue = pixelValue0 | (pixelValue1 << 8) | (pixelValue2 << 16) 
                c.io.video.expectDequeue(
                  signalType.Lit(
                    _.pixelData -> pixelValue.U,
                    _.startOfFrame -> startOfFrame.B,
                    _.endOfLine -> (x == (width / 2) - 1 && xx == 1).B,
                  )
                )
              })
            })
          })
        })
      })
      c.io.video.expectInvalid()
    }
  }
  it should "16bit" in {
    test(new FrameBufferReaderTestSystem(1, 16)).withAnnotations(Seq(VerilatorBackendAnnotation)) { c =>
      val width = c.params.pixelsH
      val height = c.params.pixelsV
      c.clock.setTimeout(width * height * 2 )
      c.io.video.initSink().setSinkClock(c.clock)
      val signalType = chiselTypeOf(c.io.video.bits)
      (0 to (width * height * 2) - 1).foreach(i => {
        val pixelAddress = i % (width * height)
        val startOfFrame = pixelAddress == 0
        c.io.forceTrigger.poke(startOfFrame.B)

        val pixelValueBase = BigInt(pixelAddress * 2)
        val pixelValue0 = (pixelValueBase + 0) & 0xff
        val pixelValue1 = (pixelValueBase + 1) & 0xff
        val pixelValue = pixelValue0 | (pixelValue1 << 8)
        c.io.video.expectDequeue(
          signalType.Lit(
            _.pixelData -> pixelValue.U,
            _.startOfFrame -> startOfFrame.B,
            _.endOfLine -> (i % width == width - 1).B
          )
        )
      })

      c.io.video.expectInvalid()
    }
  }
}
