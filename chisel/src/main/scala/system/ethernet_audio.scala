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

@chiselName
class EthernetAudioSystem(mainClockFrequencyHz: BigInt) extends RawModule {
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

  val dbg_buffering = IO(Output(Bool()))
  val dbg_probeOut = IO(Output(Bool()))

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
      (context => context.destinationPort === 10000.U),
      (context => context.destinationPort === 10001.U),
      (context => context.destinationPort === 10002.U),
      (context => context.destinationPort === 10003.U),
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
    val attenuation = 4
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

    // Construct embedded logic probe
    val probe = Module(new diag.Probe(new diag.ProbeConfig(bufferDepth = 512, triggerPosition = 512 - 16), 33))
    probe.io.in := Cat(dbg_buffering, dbg_bufferCount)
    probe.io.trigger := dbg_buffering
    val probeFrameAdapter = Module(new diag.ProbeFrameAdapter(probe.width))
    probeFrameAdapter.io.in <> probe.io.out
    val probeUartTx = Module(new UartTx(numberOfBits = 8, baudDivider = (mainClockFrequencyHz / BigInt(115200)).toInt))
    probeUartTx.io.in <> probeFrameAdapter.io.out
    dbg_probeOut := probeUartTx.io.tx
  }
}

/**
  * Elaborate EthernetAudioSystem.
  * 
  */
object ElaborateEthernetAudioSystem extends App {
  val directory = args(0)
  val mainClockFrequencyHz = args(1).toInt
  (new ChiselStage).emitVerilog(new EthernetAudioSystem(mainClockFrequencyHz = mainClockFrequencyHz), Array(
    "-o", "ethernet_audio.v",
    "--target-dir", directory,
  ))
}
