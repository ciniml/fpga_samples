// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package ethernet

import chisel3._
import chisel3.util._
import chisel3.experimental.ChiselEnum
import chisel3.experimental.BundleLiterals._
import _root_.util._

class UdpServicePort(streamWidth: Int = 1) extends Bundle {
    val udpReceiveData = Flipped(Irrevocable(MultiByteSymbol(streamWidth)))
    val udpReceiveContext = Flipped(Irrevocable(new UdpContext))
    val udpSendData = Irrevocable(MultiByteSymbol(streamWidth))
    val udpSendContext = Irrevocable(new UdpContext)
}

object UdpServicePort {
    def apply(streamWidth: Int = 1): UdpServicePort  = {
        new UdpServicePort(streamWidth)
    }
}

class UdpServiceMux( streamWidth: Int = 1, serviceMap: Seq[UdpContext => Bool]) extends Module {
    val io = IO(new Bundle {
        val in = UdpServicePort(streamWidth)
        val servicePorts = Vec(serviceMap.length, Flipped(UdpServicePort(streamWidth)))
    })

    val numberOfServices = serviceMap.length
    val numberOfPorts = numberOfServices + 1
    val demuxDiscardChannel = numberOfPorts - 1
    val demuxDisableChannel = numberOfPorts
    val muxDisableChannel = numberOfServices

    val udpReceiveDataDemux = Module(new IrrevocableDemux(MultiByteSymbol(streamWidth), numberOfPorts))
    val udpReceiveContextDemux = Module(new IrrevocableDemux(new UdpContext, numberOfPorts))
    val udpSendDataMux = Module(new IrrevocableMux(MultiByteSymbol(streamWidth), numberOfServices))
    val udpSendContextMux = Module(new IrrevocableMux(new UdpContext, numberOfServices))
    val demuxSelect = RegInit(numberOfPorts.U(log2Ceil(numberOfPorts + 1).W))
    val muxSelect = RegInit(numberOfServices.U(log2Ceil(numberOfServices + 1).W))

    udpReceiveDataDemux.io.in <> io.in.udpReceiveData
    udpReceiveContextDemux.io.in <> io.in.udpReceiveContext
    udpSendDataMux.io.out <> io.in.udpSendData
    udpSendContextMux.io.out <> io.in.udpSendContext

    val dataDemuxEnable = RegInit(false.B)
    val contextDemuxEnable = RegInit(false.B)    
    val dataMuxEnable = RegInit(false.B)
    val contextMuxEnable = RegInit(false.B)

    udpReceiveDataDemux.io.select := Mux(dataDemuxEnable, demuxSelect, numberOfPorts.U)
    udpReceiveContextDemux.io.select := Mux(contextDemuxEnable, demuxSelect, numberOfPorts.U)
    udpSendDataMux.io.select := Mux(dataMuxEnable, muxSelect, numberOfServices.U)
    udpSendContextMux.io.select := Mux(contextMuxEnable, muxSelect, numberOfServices.U)
    udpReceiveDataDemux.io.out(demuxDiscardChannel).ready := true.B       // Discard inputs
    udpReceiveContextDemux.io.out(demuxDiscardChannel).ready := true.B    // 

    for(channelIndex <- (0 to numberOfServices - 1).reverse) {
        io.servicePorts(channelIndex).udpReceiveContext <> udpReceiveContextDemux.io.out(channelIndex)
        io.servicePorts(channelIndex).udpReceiveData <> udpReceiveDataDemux.io.out(channelIndex)
        io.servicePorts(channelIndex).udpSendContext <> udpSendContextMux.io.in(channelIndex)
        io.servicePorts(channelIndex).udpSendData <> udpSendDataMux.io.in(channelIndex)
    }

    // Demux operation
    // Check UdpContext and determine which service is targeted for.
    // (Usually by checking the destination port number)
    val demuxInPacket = RegInit(false.B)
    when(!demuxInPacket) {
        when(io.in.udpReceiveContext.valid) {
            demuxSelect := demuxDiscardChannel.U
            for(channelIndex <- (0 to numberOfServices - 1).reverse) {  // Check the condition from the last service to prioritize
                when( serviceMap(channelIndex)(io.in.udpReceiveContext.bits) ) {
                    demuxSelect := channelIndex.U
                }
            }
            contextDemuxEnable := true.B
            dataDemuxEnable := true.B
            demuxInPacket := true.B
        }
    } .otherwise {
        when( udpReceiveDataDemux.io.out(demuxSelect).valid && udpReceiveDataDemux.io.out(demuxSelect).ready && udpReceiveDataDemux.io.out(demuxSelect).bits.last ) {
            dataDemuxEnable := false.B
            when( !contextDemuxEnable ) {
                demuxInPacket := false.B
            }
        }
        when( udpReceiveContextDemux.io.out(demuxSelect).valid && udpReceiveContextDemux.io.out(demuxSelect).ready ) {
            contextDemuxEnable := false.B
            when( !dataDemuxEnable ) {
                demuxInPacket := false.B
            }
        }
    }

    // Mux operation
    // Just output the first channel whose request is available.
    val muxInPacket = RegInit(false.B)
    when(!muxInPacket) {
        muxSelect := muxDisableChannel.U    // Disable mux
        for(channelIndex <- (0 to numberOfServices - 1).reverse) {  // Check the condition from the last service to prioritize
            when( io.servicePorts(channelIndex).udpSendContext.valid ) {  // The service has a pending request.
                muxSelect := channelIndex.U
                contextMuxEnable := true.B
                dataMuxEnable := true.B
                muxInPacket := true.B
            }   
        }
    } .otherwise {
        // Check select channel and process its request.
        // Note that unselecting the muxes without checking current `valid` signal is allowed and ensured to generate correct Irrevocable transaction by IrrevocableMux.
        for(channelIndex <- (0 to numberOfServices - 1).reverse) {  // Check the condition from the last service to prioritize
            // Since it is not possible to select seviceMap by muxSelect signal at runtime, 
            // we must generate selectors by comparing muxSelect and channelIndex.
            when(muxSelect === channelIndex.U) {
                when( io.servicePorts(channelIndex).udpSendContext.valid && io.servicePorts(channelIndex).udpSendContext.ready ) {
                    contextMuxEnable := false.B
                    when( !dataMuxEnable ) {
                        muxInPacket := false.B
                    }
                }
                when( io.servicePorts(channelIndex).udpSendData.valid && io.servicePorts(channelIndex).udpSendData.ready && io.servicePorts(channelIndex).udpSendData.bits.last ) {
                    dataMuxEnable := false.B
                    when( !contextMuxEnable ) {
                        muxInPacket := false.B
                    }
                }
            }
        }
    }
}