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
import sound._
import _root_.util._
import diag.{Probe, ProbeFrameAdapter}
import uart.UartTx
import display.HUB75Controller
import display.HUB75IO


class EthernetVideoSystem(mainClockFrequencyHz: BigInt) extends RawModule {
  val clock = IO(Input(Clock()))
  val aresetn = IO(Input(Bool()))
  
  val rmii_clock = IO(Input(Clock()))
  val rmii_reset = IO(Input(Bool()))
  
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

  val out_ws = IO(Output(Bool()))
  val out_bclk = IO(Output(Bool()))
  val out_data = IO(Output(Bool()))

  val hub75io = IO(HUB75IO(2))

  val dbg_buffering = IO(Output(Bool()))
  val dbg_probeOut = IO(Output(Bool()))

  def rgb565ToRgb666(rgb565: UInt): UInt = {
    val r = Cat(rgb565(15, 11), rgb565(11))
    val g = rgb565(10, 5)
    val b = Cat(rgb565(4, 0), rgb565(0))
    Cat(r, g, b)
  }

  val txAsyncFifo = withClockAndReset(rmii_clock, rmii_reset) { Module(new AsyncFIFO(Flushable(UInt(8.W)), 3))}
  val rxAsyncFifo = withClockAndReset(rmii_clock, rmii_reset) { Module(new AsyncFIFO(Flushable(UInt(8.W)), 3))}

  val txFifo = txAsyncFifo
  val rxFifo = rxAsyncFifo
  txFifo.io.readClock := rmii_clock
  txFifo.io.readReset := rmii_reset
  txFifo.io.writeClock := clock
  txFifo.io.writeReset := !aresetn

  txFifo.io.read.valid <> out_tvalid
  txFifo.io.read.ready <> out_tready
  txFifo.io.read.bits.data <> out_tdata
  txFifo.io.read.bits.last <> out_tlast

  rxFifo.io.readClock := clock
  rxFifo.io.readReset := !aresetn
  rxFifo.io.writeClock := rmii_clock
  rxFifo.io.writeReset := rmii_reset

  rxFifo.io.write.valid <> in_tvalid
  rxFifo.io.write.ready <> in_tready
  rxFifo.io.write.bits.data <> in_tdata
  rxFifo.io.write.bits.last <> in_tlast

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

    rxQueue.io.enq.valid <> rxAsyncFifo.io.read.valid
    rxQueue.io.enq.ready <> rxAsyncFifo.io.read.ready
    rxQueue.io.enq.bits.data <> rxAsyncFifo.io.read.bits.data
    rxQueue.io.enq.bits.last <> rxAsyncFifo.io.read.bits.last

    txPacketQueue.io.read.valid <> txAsyncFifo.io.write.valid
    txPacketQueue.io.read.ready <> txAsyncFifo.io.write.ready
    txPacketQueue.io.read.bits.data <> txAsyncFifo.io.write.bits.data
    txPacketQueue.io.read.bits.last <> txAsyncFifo.io.write.bits.last
  
    val audioChannels = 2
    val serviceMux = Module(new UdpServiceMux(1, Seq(
      (context => context.destinationPort === 10000.U), // Loopback
      (context => context.destinationPort === 10001.U), // GPIO 
      (context => context.destinationPort === 10002.U), // Audio 1
      (context => context.destinationPort === 10003.U), // Audio 2
      (context => context.destinationPort === 10004.U), // Video
    )))
    service.io.port <> serviceMux.io.in

    val udpLoopback = Module(new UdpLoopback)
    serviceMux.io.servicePorts(0) <> udpLoopback.io.port

    val udpGpio = Module(new UdpGpio(numOutputBits = 72))
    serviceMux.io.servicePorts(1) <> udpGpio.io.port
    gpio_out := udpGpio.io.gpioOut
    udpGpio.io.gpioIn := gpio_in
    val volumeControl = udpGpio.io.gpioOut(71, 8)

    val dbg_bufferCount = WireDefault(0.U(32.W))
    val dbg_probeSignals = WireDefault(0.U(10.W))
    val dbg_probeTrigger = WireDefault(false.B)

    val sampleRate = 48000
    val master = Module(new I2sMaster(16, (mainClockFrequencyHz / sampleRate / 2).toInt, 0))
    val audioMixer = Module(new AudioMixerXls(16, audioChannels, 0))
    val audioSampler = Module(new AudioSampler(16, audioChannels, 0, (mainClockFrequencyHz / sampleRate).toInt))
    for(channelIndex <- 0 until audioMixer.channels) {
      val audioBufferSize = 2048
      val backPressureThreshold = audioBufferSize * 3 / 4
      val udpStream = Module(new UdpStreamWriter(backPressureMaxBufferSize = Some(audioBufferSize)))
      serviceMux.io.servicePorts(2 + channelIndex) <> udpStream.io.port
      
      val widthConverter = Module(WidthConverter(8, 32))
      widthConverter.io.enq.valid     <> udpStream.io.dataReceived.valid
      widthConverter.io.enq.ready     <> udpStream.io.dataReceived.ready
      widthConverter.io.enq.bits.data <> udpStream.io.dataReceived.bits.data
      widthConverter.io.enq.bits.last <> udpStream.io.dataReceived.bits.last

      val widthConverterDeq = Wire(Decoupled(UInt(32.W)))
      widthConverterDeq.valid <> widthConverter.io.deq.valid
      widthConverterDeq.ready <> widthConverter.io.deq.ready
      widthConverterDeq.bits  <> widthConverter.io.deq.bits.data
      
      val audioBuffer = Module(new AudioBuffer(32, audioBufferSize, audioBufferSize))
      audioBuffer.io.dataIn <> widthConverterDeq
      audioSampler.io.dataIn(channelIndex) <> audioBuffer.io.dataOut
      val audioBufferFilled = audioBuffer.io.bufferedEntries >= backPressureThreshold.U
      val audioBufferFilledReg = RegNext(audioBufferFilled, false.B)
      val backPressure = udpStream.io.backPressure.get
      backPressure.valid := audioBufferFilledReg && !audioBufferFilled
      backPressure.bits := audioBuffer.io.bufferedEntries

      if( channelIndex == 0 ) { 
        audioMixer.io.dataIn(channelIndex) <> audioSampler.io.dataOut(channelIndex)
      } else {
        val filter = Module(new AudioMovingAverageFilter(16, 8))
        filter.io.dataIn <> audioSampler.io.dataOut(channelIndex)
        audioMixer.io.dataIn(channelIndex) <> filter.io.dataOut
      }

      audioMixer.io.volumeIn(channelIndex).bits := volumeControl(32*(channelIndex + 1)-1, 32*channelIndex) // "x80008000".U
      audioMixer.io.volumeIn(channelIndex).valid := true.B

      if( channelIndex == 0 ) {
        dbg_buffering := audioBuffer.io.buffering
        dbg_bufferCount := audioBuffer.io.bufferedEntries
      }
    }

    master.io.dataIn.valid <> audioMixer.io.dataOut.valid
    master.io.dataIn.ready <> audioMixer.io.dataOut.ready
    val attenuation = 0
    if( attenuation > 0 ) {
      val lch = (audioMixer.io.dataOut.bits(15, 0) >> attenuation)
      val rch = (audioMixer.io.dataOut.bits(31, 16) >> attenuation)
      master.io.dataIn.bits := Cat(Fill(attenuation, rch(15-attenuation)), rch, Fill(attenuation, lch(15-attenuation)), lch)
    } else {
      master.io.dataIn.bits := audioMixer.io.dataOut.bits
    }

    // Video output (HUB75)
    {
      val hub75Width = 64
      val hub75Height = 32
      val bytesPerPixel = 2
      val numberOfPanels = 2
      val numberOfFrameBuffers = 3
      val clockDivider = 0  // 18MHz
      val hub75 = Module(new HUB75Controller(hub75Width, hub75Height, numberOfPanels, pixelComponentBits = 6, clockDivider = clockDivider.toInt))
      val frameRateHz = 30
      val frameRateDivider = (mainClockFrequencyHz + frameRateHz - 1) / frameRateHz
      val frameRateCounter = RegInit(0.U(log2Ceil(frameRateDivider).W))

      // Frame buffers.
      // For each frame buffer, we have two buffers for `numberOfPanels` panels.
      val maxPixelAddress = hub75Width*hub75Height*numberOfFrameBuffers
      val frameBuffers = (0 to numberOfPanels - 1).map(_ => Mem(maxPixelAddress, Vec(2, UInt(8.W))))
      val renderingBufferIndex = RegInit(0.U(log2Ceil(numberOfFrameBuffers).W))
      val receivingBufferIndex = RegInit(0.U(log2Ceil(numberOfFrameBuffers).W))
      val nextPixelAddress = WireDefault(0.U(log2Ceil(maxPixelAddress).W))
      for(panelIndex <- 0 to numberOfPanels - 1) {
        hub75.io.panelPixels(panelIndex).pixel := rgb565ToRgb666(frameBuffers(panelIndex).read(nextPixelAddress).asUInt)
      }
      for(bufferIndex <- 0 to numberOfFrameBuffers - 1) {
        when( renderingBufferIndex === bufferIndex.U ) {
          nextPixelAddress := hub75.io.panelPixels(0).address + (hub75Width*hub75Height*bufferIndex).U
        }
      }

      val nextFrame = WireDefault(false.B)
      val advanceRenderingBufferIndex = WireDefault(false.B)
      val pendingNextRenderingFrame = RegInit(false.B)
      frameRateCounter := frameRateCounter + 1.U
      when( frameRateCounter === (frameRateDivider - 1).U ) {
        frameRateCounter := 0.U
        nextFrame := true.B
      }
      when( nextFrame ) {
        pendingNextRenderingFrame := true.B
      }
      when( hub75.io.endOfFrame ) {
        // Advance the rendering buffer index if there is a next buffer available.
        when( renderingBufferIndex =/= receivingBufferIndex && (pendingNextRenderingFrame || nextFrame)) {
          val nextRenderingBufferIndex = Mux(renderingBufferIndex < (numberOfFrameBuffers - 1).U, renderingBufferIndex + 1.U, 0.U)
          when( nextRenderingBufferIndex =/= receivingBufferIndex) {
            renderingBufferIndex := nextRenderingBufferIndex
          }
          pendingNextRenderingFrame := false.B
          advanceRenderingBufferIndex := true.B
        }
      }

      val udpWriter = Module(new UdpMemoryWriter(numMemoryBytes = hub75Width*hub75Height*numberOfPanels*bytesPerPixel, backPressureDataSize = Some(32), enableDebug = true))
      serviceMux.io.servicePorts(4) <> udpWriter.io.port
      val backPressureValid = RegInit(false.B)
      when( udpWriter.io.backPressure.get.fire ) {
        backPressureValid := false.B
      }
      when( advanceRenderingBufferIndex ) {
        backPressureValid := true.B
      }
      udpWriter.io.backPressure.get.valid := backPressureValid
      udpWriter.io.backPressure.get.bits := "xdeadbeef".U
      
      when( udpWriter.io.writeEnable ) {
        val mask = VecInit(!udpWriter.io.address(0), udpWriter.io.address(0))
        val value = VecInit(Seq.fill(2)(udpWriter.io.data))
        val accessToLastByte = WireDefault(false.B)
        val frameBufferAddressOffset = WireDefault(0.U(log2Ceil(maxPixelAddress).W))
        // Calculate frame buffer offset
        for(bufferIndex <- 0 to numberOfFrameBuffers - 1) {
          when( receivingBufferIndex === bufferIndex.U ) {
            frameBufferAddressOffset := (hub75Width*hub75Height*bufferIndex).U
          }
        }
        for(panelIndex <- 0 to numberOfPanels - 1) {
          val panelLowerAddress = panelIndex * hub75Width * hub75Height * bytesPerPixel
          val panelUpperAddress = (panelIndex + 1) * hub75Width * hub75Height * bytesPerPixel - 1
          when( panelLowerAddress.U <= udpWriter.io.address && udpWriter.io.address <= panelUpperAddress.U ) {
            frameBuffers(panelIndex).write(((udpWriter.io.address - panelLowerAddress.U) >> 1) + frameBufferAddressOffset, value, mask)
          }
        }
        when( udpWriter.io.address === (hub75Width * hub75Height * bytesPerPixel * numberOfPanels - 1).U ) {
          // Access to the last byte of the frame buffer. Advance the receiving buffer index.
          receivingBufferIndex := Mux(receivingBufferIndex < (numberOfFrameBuffers - 1).U, receivingBufferIndex + 1.U, 0.U)
        }
      }
      hub75io <> hub75.io.hub75

      dbg_probeSignals := Cat(receivingBufferIndex, renderingBufferIndex, service.io.port.udpSendData.ready, service.io.port.udpSendData.valid, service.io.port.udpSendContext.ready, service.io.port.udpSendContext.valid, backPressureValid, advanceRenderingBufferIndex)
      dbg_probeTrigger := advanceRenderingBufferIndex
    }

    // val clockEnable = RegInit(false.B)
    // clockEnable := !clockEnable
    // master.io.clockEnable := clockEnable
    // out_bclk := clockEnable
    master.io.clockEnable := true.B
    out_bclk := clock.asBool
    out_data := master.io.dataOut
    out_ws := master.io.wordSelect

    // Construct embedded logic probe
    val probe = Module(new diag.Probe(new diag.ProbeConfig(bufferDepth = 512, triggerPosition = 16), dbg_probeSignals.getWidth))
    probe.io.in := dbg_probeSignals
    probe.io.trigger := dbg_probeTrigger
    val probeFrameAdapter = Module(new diag.ProbeFrameAdapter(probe.width))
    probeFrameAdapter.io.in <> probe.io.out
    val probeUartTx = Module(new UartTx(numberOfBits = 8, baudDivider = (mainClockFrequencyHz / BigInt(115200)).toInt))
    probeUartTx.io.in <> probeFrameAdapter.io.out
    dbg_probeOut := probeUartTx.io.tx
  }
}

/**
  * Elaborate EthernetVideoSystem.
  * 
  */
object ElaborateEthernetVideoSystem extends App {
  val directory = args(0)
  val mainClockFrequencyHz = args(1).toInt
  ChiselStage.emitSystemVerilogFile(new EthernetVideoSystem(mainClockFrequencyHz = mainClockFrequencyHz), Array(
    "-o", "ethernet_video.v",
    "--target-dir", directory,
  ))
}
