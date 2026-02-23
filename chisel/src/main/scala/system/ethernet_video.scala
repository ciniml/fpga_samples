// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._
import chisel3.experimental.chiselName
import chisel3.stage.ChiselStage

import ethernet._
import sound._
import _root_.util._
import diag.{Probe, ProbeFrameAdapter}
import uart.UartTx
import display.HUB75Controller
import display.HUB75IO

@chiselName
class EthernetVideoSystem(mainClockFrequencyHz: BigInt, useAudio: Boolean = true, ethernetWidthBits: Int = 8, maxFrameSize: Int = 2048, useRgb332: Boolean = false, hub75Width: Int = 128, numberOfPanels: Int = 2) extends RawModule {
  assert(ethernetWidthBits % 8 == 0)
  val ethernetWidthBytes = ethernetWidthBits / 8

  val clock = IO(Input(Clock()))
  val aresetn = IO(Input(Bool()))
  
  val rmii_clock = IO(Input(Clock()))
  val rmii_reset = IO(Input(Bool()))
  
  val in_tdata = IO(Input(UInt(ethernetWidthBits.W)))
  val in_tvalid = IO(Input(Bool()))
  val in_tready = IO(Output(Bool()))
  val in_tkeep = IO(Input(UInt(ethernetWidthBytes.W)))
  val in_tlast = IO(Input(Bool()))

  val out_tdata = IO(Output(UInt(ethernetWidthBits.W)))
  val out_tvalid = IO(Output(Bool()))
  val out_tready = IO(Input(Bool()))
  val out_tkeep = IO(Output(UInt(ethernetWidthBytes.W)))
  val out_tlast = IO(Output(Bool()))

  val gpio_in = IO(Input(UInt(8.W)))
  val gpio_out = IO(Output(UInt(72.W)))

  val out_ws = IO(Output(Bool()))
  val out_bclk = IO(Output(Bool()))
  val out_data = IO(Output(Bool()))

  val hub75io = IO(HUB75IO(numberOfPanels))

  val dbg_buffering = IO(Output(Bool()))
  val dbg_probeOut = IO(Output(Bool()))

  def rgb565ToRgb666(rgb565: UInt): UInt = {
    val r = Cat(rgb565(15, 11), rgb565(11))
    val g = rgb565(10, 5)
    val b = Cat(rgb565(4, 0), rgb565(0))
    Cat(r, g, b)
  }
  def rgb332ToRgb666(rgb332: UInt): UInt = {
    val r_3 = rgb332(7, 5)
    val g_3 = rgb332(4, 2)
    val b_2 = rgb332(1, 0)
    val r = Cat(r_3, r_3)
    val g = Cat(g_3, g_3)
    val b = Cat(b_2, b_2, b_2)
    Cat(r, g, b)
  }

  val ethernetFifoDepth = (maxFrameSize + ethernetWidthBytes - 1) / ethernetWidthBytes

  val (txAsyncFifo, rxAsyncFifo) = withClockAndReset(rmii_clock, rmii_reset) {
    val txAsyncFifo = Module(new AsyncFIFO(MultiByteSymbol(1), 3))
    val rxAsyncFifo = Module(new AsyncFIFO(MultiByteSymbol(1), 3))

    val ethernetDataType = MultiByteSymbol(ethernetWidthBytes)

    val rxQueue = Module(new Queue(ethernetDataType, ethernetFifoDepth))
    val txQueue = Module(PacketQueue(ethernetDataType.flushableType, ethernetFifoDepth))
    
    rxQueue.io.enq.valid := in_tvalid
    rxQueue.io.enq.bits.data := in_tdata
    rxQueue.io.enq.bits.keep := in_tkeep
    rxQueue.io.enq.bits.last := in_tlast
    in_tready := rxQueue.io.enq.ready
    
    val txQueueBits = Wire(ethernetDataType)
    txQueueBits.fromFlushable(txQueue.io.read.bits)
    out_tvalid := txQueue.io.read.valid
    out_tdata := txQueueBits.data
    out_tkeep := txQueueBits.keep
    out_tlast := txQueueBits.last
    txQueue.io.read.ready := out_tready

    if(ethernetWidthBits != 8 ) {
      val rxWidthConverter = Module(new WidthConverterWithKeep(ethernetWidthBits, 8))
      val txWidthConverter = Module(new WidthConverterWithKeep(8, ethernetWidthBits))

      rxWidthConverter.io.enq <> rxQueue.io.deq
      rxAsyncFifo.io.write <> rxWidthConverter.io.deq

      txQueue.io.write.valid <> txWidthConverter.io.deq.valid
      txQueue.io.write.ready <> txWidthConverter.io.deq.ready
      txQueue.io.write.bits := txWidthConverter.io.deq.bits.toFlushable
      txWidthConverter.io.enq <> txAsyncFifo.io.read
    } else {
      rxAsyncFifo.io.write <> rxQueue.io.deq
      txQueue.io.write.valid <> txAsyncFifo.io.read.valid
      txQueue.io.write.ready <> txAsyncFifo.io.read.ready
      txQueue.io.write.bits := txAsyncFifo.io.read.bits.toFlushable
    }

    (txAsyncFifo, rxAsyncFifo)
  }

  txAsyncFifo.io.readClock := rmii_clock
  txAsyncFifo.io.readReset := rmii_reset
  txAsyncFifo.io.writeClock := clock
  txAsyncFifo.io.writeReset := !aresetn

  rxAsyncFifo.io.readClock := clock
  rxAsyncFifo.io.readReset := !aresetn
  rxAsyncFifo.io.writeClock := rmii_clock
  rxAsyncFifo.io.writeReset := rmii_reset

  withClockAndReset(clock, !aresetn) {
    val service = Module(new EthernetService)
    service.io.in <> rxAsyncFifo.io.read
    service.io.out <> txAsyncFifo.io.write

    val audioChannels = 2
    val serviceMux = Module(new UdpServiceMux(1, Seq(
      Some((context: UdpContext) => context.destinationPort === 10000.U), // Loopback
      Some((context: UdpContext) => context.destinationPort === 10001.U), // GPIO 
      if(useAudio) { Some((context: UdpContext) => context.destinationPort === 10002.U) } else { None }, // Audio 1
      if(useAudio) { Some((context: UdpContext) => context.destinationPort === 10003.U) } else { None }, // Audio 2
      Some((context: UdpContext) => context.destinationPort === 10004.U), // Video
    ).flatMap(x => x)))
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

    dbg_probeTrigger := txAsyncFifo.io.write.valid
    dbg_probeSignals := Cat(txAsyncFifo.io.write.bits.last, txAsyncFifo.io.write.valid, txAsyncFifo.io.write.bits.data)

    if( useAudio ) {
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

      // val clockEnable = RegInit(false.B)
      // clockEnable := !clockEnable
      // master.io.clockEnable := clockEnable
      // out_bclk := clockEnable
      master.io.clockEnable := true.B
      out_bclk := clock.asBool
      out_data := master.io.dataOut
      out_ws := master.io.wordSelect
    } else {
      dbg_buffering := false.B
      out_bclk := false.B
      out_data := false.B
      out_ws := false.B
    }

    // Video output (HUB75)
    {
      //val hub75Width = 128  // passed by parameter
      val hub75Height = 32
      val bytesPerPixel = if( useRgb332 ) { 1 } else { 2 }
      //val numberOfPanels = 2  // passed by parameter
      val numberOfFrameBuffers = 2
      val clockDivider = 0  // 18MHz
      val hub75 = Module(new HUB75Controller(hub75Width, hub75Height, numberOfPanels, pixelComponentBits = 6, clockDivider = clockDivider.toInt))
      val frameRateHz = 20
      val frameRateDivider = (mainClockFrequencyHz + frameRateHz - 1) / frameRateHz
      val frameRateCounter = RegInit(0.U(log2Ceil(frameRateDivider).W))

      // Frame buffers.
      // For each frame buffer, we have two buffers for `numberOfPanels` panels.
      val maxPixelAddress = hub75Width*hub75Height*numberOfFrameBuffers
      val frameBuffers = (0 to numberOfPanels - 1).map(_ => Mem(maxPixelAddress, Vec(bytesPerPixel, UInt(8.W))))
      val renderingBufferIndex = RegInit(0.U(log2Ceil(numberOfFrameBuffers).W))
      val receivingBufferIndex = RegInit(0.U(log2Ceil(numberOfFrameBuffers).W))
      val nextPixelAddress = WireDefault(0.U(log2Ceil(maxPixelAddress).W))
      for(panelIndex <- 0 to numberOfPanels - 1) {
        if( useRgb332 ) {
          hub75.io.panelPixels(panelIndex).pixel := rgb332ToRgb666(frameBuffers(panelIndex).read(nextPixelAddress).asUInt)
        } else {
          hub75.io.panelPixels(panelIndex).pixel := rgb565ToRgb666(frameBuffers(panelIndex).read(nextPixelAddress).asUInt)
        }
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
      serviceMux.io.servicePorts.last <> udpWriter.io.port
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
        val mask = if( bytesPerPixel == 2 ) { VecInit(!udpWriter.io.address(0), udpWriter.io.address(0)) } else { VecInit(true.B) }
        val value =  if( bytesPerPixel == 2 ) { VecInit(Seq.fill(2)(udpWriter.io.data)) } else { VecInit(Seq(udpWriter.io.data)) }
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
            frameBuffers(panelIndex).write(((udpWriter.io.address - panelLowerAddress.U) / bytesPerPixel.U) + frameBufferAddressOffset, value, mask)
          }
        }
        when( udpWriter.io.address === (hub75Width * hub75Height * bytesPerPixel * numberOfPanels - 1).U ) {
          // Access to the last byte of the frame buffer. Advance the receiving buffer index.
          receivingBufferIndex := Mux(receivingBufferIndex < (numberOfFrameBuffers - 1).U, receivingBufferIndex + 1.U, 0.U)
        }
      }
      hub75io <> hub75.io.hub75

      // dbg_probeSignals := Cat(receivingBufferIndex, renderingBufferIndex, service.io.port.udpSendData.ready, service.io.port.udpSendData.valid, service.io.port.udpSendContext.ready, service.io.port.udpSendContext.valid, backPressureValid, advanceRenderingBufferIndex)
      // dbg_probeTrigger := advanceRenderingBufferIndex
    }

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
  val useAudio = args(2).toBoolean
  val ethernetWidthBits = if(args.length >= 4) { args(3).toInt } else { 8 }
  val numberOfPanels = if(args.length >= 5) { args(4).toInt } else { 2 }
  val useRgb332 = if(args.length >= 6) { args(5) == "true" } else { false }

  (new ChiselStage).emitVerilog(new EthernetVideoSystem(mainClockFrequencyHz = mainClockFrequencyHz, useAudio = useAudio, ethernetWidthBits = ethernetWidthBits, useRgb332 = useRgb332, numberOfPanels = numberOfPanels), Array(
    "-o", "ethernet_video.v",
    "--target-dir", directory,
  ))
}
