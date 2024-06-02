// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._

import _root_.circt.stage.ChiselStage
import ethernet._
import display._
import _root_.util._




class EthernetSystem(mainClockFrequencyHz: BigInt, asyncSystemClock: Boolean = false) extends RawModule {
  val clock = IO(Input(Clock()))
  val aresetn = IO(Input(Bool()))
  
  val rmii_clock = if(asyncSystemClock) { Some(IO(Input(Clock()))) } else { None }
  val rmii_reset = if(asyncSystemClock) { Some(IO(Input(Bool()))) } else { None }
  
  val selected_rmii_clock = if(asyncSystemClock) { rmii_clock.get } else { clock }
  val selected_rmii_reset = if(asyncSystemClock) { rmii_reset.get } else { !aresetn }

  val in_tdata = IO(Input(UInt(8.W)))
  val in_tvalid = IO(Input(Bool()))
  val in_tready = IO(Output(Bool()))
  val in_tlast = IO(Input(Bool()))

  val out_tdata = IO(Output(UInt(8.W)))
  val out_tvalid = IO(Output(Bool()))
  val out_tready = IO(Input(Bool()))
  val out_tlast = IO(Output(Bool()))

  val gpio_in = IO(Input(UInt(8.W)))
  val gpio_out = IO(Output(UInt(72.W)))

  val hub75io = IO(HUB75IO(2))

  def rgb565ToRgb666(rgb565: UInt): UInt = {
    val r = Cat(rgb565(15, 11), rgb565(15))
    val g = rgb565(10, 5)
    val b = Cat(rgb565(4, 0), rgb565(4))
    Cat(r, g, b)
  }

  val txAsyncFifo = if(asyncSystemClock) { Some(withClockAndReset(rmii_clock.get, rmii_reset.get) { Module(new AsyncFIFO(Flushable(UInt(8.W)), 3))} ) } else { None }
  val rxAsyncFifo = if(asyncSystemClock) { Some(withClockAndReset(rmii_clock.get, rmii_reset.get) { Module(new AsyncFIFO(Flushable(UInt(8.W)), 3))} ) } else { None }

  if(asyncSystemClock) {
    val txFifo = txAsyncFifo.get
    val rxFifo = rxAsyncFifo.get
    txFifo.io.readClock := rmii_clock.get
    txFifo.io.readReset := rmii_reset.get
    txFifo.io.writeClock := clock
    txFifo.io.writeReset := !aresetn

    txFifo.io.read.valid <> out_tvalid
    txFifo.io.read.ready <> out_tready
    txFifo.io.read.bits.data <> out_tdata
    txFifo.io.read.bits.last <> out_tlast

    rxFifo.io.readClock := clock
    rxFifo.io.readReset := !aresetn
    rxFifo.io.writeClock := rmii_clock.get
    rxFifo.io.writeReset := rmii_reset.get

    rxFifo.io.write.valid <> in_tvalid
    rxFifo.io.write.ready <> in_tready
    rxFifo.io.write.bits.data <> in_tdata
    rxFifo.io.write.bits.last <> in_tlast
  
  }

  withClockAndReset(clock, !aresetn) {
    val service = Module(new EthernetService)
    
    val rxQueue = Module(new Queue(Flushable(UInt(8.W)), 2048))
    rxQueue.io.deq.valid <> service.io.in.valid
    rxQueue.io.deq.ready <> service.io.in.ready
    rxQueue.io.deq.bits.data <> service.io.in.bits.data
    rxQueue.io.deq.bits.last <> service.io.in.bits.last
    service.io.in.bits.keep := 1.U

    val txPacketQueue = Module(new PacketQueue(Flushable(UInt(8.W)), 2048))
    txPacketQueue.io.write.valid <> service.io.out.valid
    txPacketQueue.io.write.ready <> service.io.out.ready
    txPacketQueue.io.write.bits.data <> service.io.out.bits.data
    txPacketQueue.io.write.bits.last <> service.io.out.bits.last

    if(asyncSystemClock) {
      rxQueue.io.enq.valid <> rxAsyncFifo.get.io.read.valid
      rxQueue.io.enq.ready <> rxAsyncFifo.get.io.read.ready
      rxQueue.io.enq.bits.data <> rxAsyncFifo.get.io.read.bits.data
      rxQueue.io.enq.bits.last <> rxAsyncFifo.get.io.read.bits.last

      txPacketQueue.io.read.valid <> txAsyncFifo.get.io.write.valid
      txPacketQueue.io.read.ready <> txAsyncFifo.get.io.write.ready
      txPacketQueue.io.read.bits.data <> txAsyncFifo.get.io.write.bits.data
      txPacketQueue.io.read.bits.last <> txAsyncFifo.get.io.write.bits.last
    } else {
      rxQueue.io.enq.valid <> in_tvalid
      rxQueue.io.enq.ready <> in_tready
      rxQueue.io.enq.bits.data <> in_tdata
      rxQueue.io.enq.bits.last <> in_tlast

      txPacketQueue.io.read.valid <> out_tvalid
      txPacketQueue.io.read.ready <> out_tready
      txPacketQueue.io.read.bits.data <> out_tdata
      txPacketQueue.io.read.bits.last <> out_tlast
    }

    val serviceMux = Module(new UdpServiceMux(1, Seq(
      (context => context.destinationPort === 10000.U),
      (context => context.destinationPort === 10001.U),
      (context => context.destinationPort === 10002.U),
    )))
    service.io.port <> serviceMux.io.in

    val udpLoopback = Module(new UdpLoopback)
    serviceMux.io.servicePorts(0) <> udpLoopback.io.port

    val udpGpio = Module(new UdpGpio(numOutputBits = 72))
    serviceMux.io.servicePorts(1) <> udpGpio.io.port
    gpio_out := udpGpio.io.gpioOut
    udpGpio.io.gpioIn := gpio_in

    val hub75Width = 64
    val hub75Height = 32
    val bytesPerPixel = 2
    val numberOfPanels = 2
    val clockDivider = (20000000 + mainClockFrequencyHz - 1) / mainClockFrequencyHz
    val hub75 = Module(new HUB75Controller(hub75Width, hub75Height, numberOfPanels, pixelComponentBits = 6, clockDivider = clockDivider.toInt))
    //val hub75 = Module(new HUB75Controller(hub75Width, hub75Height, 2))
    val hub75PixelsUpper = Mem(hub75Width*hub75Height, Vec(2, UInt(8.W)))
    val hub75PixelsLower = Mem(hub75Width*hub75Height, Vec(2, UInt(8.W)))
    hub75.io.panelPixels(0).pixel := rgb565ToRgb666(hub75PixelsUpper.read(hub75.io.panelPixels(0).address).asUInt)
    hub75.io.panelPixels(1).pixel := rgb565ToRgb666(hub75PixelsLower.read(hub75.io.panelPixels(1).address).asUInt)
    val udpWriter = Module(new UdpMemoryWriter(numMemoryBytes = hub75Width*hub75Height*numberOfPanels*bytesPerPixel))
    serviceMux.io.servicePorts(2) <> udpWriter.io.port

    when( udpWriter.io.writeEnable ) {
      val mask = VecInit(!udpWriter.io.address(0), udpWriter.io.address(0))
      val value = VecInit(Seq.fill(2)(udpWriter.io.data))
      when(udpWriter.io.address < (hub75Width*hub75Height*bytesPerPixel).U) {
        hub75PixelsUpper.write(udpWriter.io.address >> 1, value, mask)
      } .elsewhen(udpWriter.io.address < (hub75Width*hub75Height*bytesPerPixel*numberOfPanels).U) {
        hub75PixelsLower.write(udpWriter.io.address >> 1, value, mask)
      }
    }
    hub75io <> hub75.io.hub75
  }
}

object ElaborateEthernetSystem extends App {
  ChiselStage.emitSystemVerilogFile(new EthernetSystem(50000000), Array(
    "-o", "ethernet_system.v",
    "--target-dir", "rtl/chisel/ethernet_system",
  ))
}

object ElaborateAsyncEthernetSystem extends App {
  ChiselStage.emitSystemVerilogFile(new EthernetSystem(20000000, true), Array(
    "-o", "ethernet_system_async.v",
    "--target-dir", "rtl/chisel/ethernet_system",
  ))
}
