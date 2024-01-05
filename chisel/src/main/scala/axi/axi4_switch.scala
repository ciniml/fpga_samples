// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package axi

import chisel3._
import chisel3.util._
import chisel3.experimental.ChiselEnum
import chisel3.{printf => chiselPrintf}

class AXI4Demux(axi4Params: AXI4Params, numberOfMasters: Int) extends Module {
    val io = IO(new Bundle {
        val in = Vec(numberOfMasters, Flipped(AXI4IO(axi4Params)))
        val out = AXI4IO(axi4Params)
    })

    val inputIndexBits = log2Ceil(numberOfMasters)
    val mode = axi4Params.mode
    val addressBits = axi4Params.addressBits
    val maxBurstLength = axi4Params.maxBurstLength.get

    mode match {
        case AXI4WriteOnly => {}
        case _ => {
            val inputIndex = RegInit(0.U(inputIndexBits.W))
            val nextInputIndex = Mux(inputIndex < (numberOfMasters - 1).U, inputIndex + 1.U, 0.U)
            val in = io.in(inputIndex)
            val sIdle :: sTransfer :: Nil = Enum(2)
            val state = RegInit(sIdle)
            
            val ar = io.out.ar.get
            val r = io.out.r.get

            val arValid = RegInit(false.B)
            val arReady = WireDefault(ar.ready)
            val arAddr = RegInit(0.U(addressBits.W))
            val arLen = RegInit(0.U(log2Ceil(maxBurstLength).W))
            ar.valid := arValid
            ar.bits.addr := arAddr
            ar.bits.len.get := arLen

            val rValid = WireDefault(r.valid)
            val rReady = WireDefault(false.B)
            val rData = WireDefault(r.bits.data)
            val rLast = WireDefault(r.bits.last.get)
            val rResp = WireDefault(r.bits.resp)
            r.ready := rReady
            
            // Connect AR and R slave->master signals
            for(i <- 0 to numberOfMasters - 1) {
                val in = io.in(i)
                val selected = i.U === inputIndex
                in.ar.get.ready := selected && arReady && state === sIdle
                in.r.get.valid := selected && rValid && state === sTransfer
                in.r.get.bits := r.bits
            }

            // Clear ARVALID if the last transaction completes.
            when(arValid && arReady) {
                arValid := false.B
            }

            switch(state) {
                is(sIdle) {
                    when(in.ar.get.valid) { // Current selected channel is ready.
                        arValid := true.B
                        arAddr := in.ar.get.bits.addr
                        arLen := in.ar.get.bits.len.get
                        state := sTransfer
                    } .otherwise {
                        inputIndex := nextInputIndex
                    }
                }
                is(sTransfer) {
                    rReady := in.r.get.ready

                    when(rValid && rReady && rLast ) {
                        state := sIdle
                        inputIndex := 0.U //nextInputIndex
                    }
                }
            }
        }
    }

    mode match {
        case AXI4ReadOnly => {}
        case _ => {
            val inputIndex = RegInit(0.U(inputIndexBits.W))
            val nextInputIndex = Mux(inputIndex < (numberOfMasters - 1).U, inputIndex + 1.U, 0.U)
            val in = io.in(inputIndex)
            val sIdle :: sTransfer :: sResp :: Nil = Enum(3)
            val state = RegInit(sIdle)
            val count = RegInit(0.U(log2Ceil(maxBurstLength).W))
            val aw = io.out.aw.get
            val w = io.out.w.get
            val b = io.out.b.get

            val awValid = RegInit(false.B)
            val awReady = WireDefault(aw.ready)
            val awAddr = RegInit(0.U(addressBits.W))
            val awLen = RegInit(0.U(log2Ceil(maxBurstLength).W))
            aw.valid := awValid
            aw.bits.addr := awAddr
            aw.bits.len.get := awLen
            
            // Connect AW, W, B slave->master signals
            for(i <- 0 to numberOfMasters - 1) {
                val in = io.in(i)
                val selected = i.U === inputIndex
                in.aw.get.ready := selected && awReady && state === sIdle
                in.w.get.ready := selected && w.ready && state === sTransfer
                in.b.get.valid := selected && b.valid && state === sResp
                in.b.get.bits := b.bits
            }

            // Clear AWVALID if the last transaction completes.
            when(awValid && awReady) {
                awValid := false.B
            }
            
            w.valid := false.B
            w.bits := DontCare
            b.ready := false.B

            switch(state) {
                is(sIdle) {
                    when(in.aw.get.valid && in.aw.get.ready) { // Current selected channel is ready.
                        printf(p"[DEMUX] Select index=${inputIndex} addr=${Hexadecimal(in.aw.get.bits.addr)} len=${Hexadecimal(in.aw.get.bits.len.get)}\n")
                        awValid := true.B
                        awAddr := in.aw.get.bits.addr
                        awLen := in.aw.get.bits.len.get
                        count := in.aw.get.bits.len.get
                        state := sTransfer
                    } .otherwise {
                        inputIndex := nextInputIndex
                    }
                }
                is(sTransfer) {
                    w.valid := in.w.get.valid
                    w.bits := in.w.get.bits
                    // when( in.w.get.valid && in.w.get.ready && in.w.get.bits.last.get ) {
                    //     state := sResp
                    // }
                    when( in.w.get.valid && in.w.get.ready ) {
                        count := count - 1.U
                        when( count === 0.U ) {
                            state := sResp
                        }
                    }
                }
                is(sResp) {
                    b.ready := in.b.get.ready
                    when(in.b.get.valid && in.b.get.ready ) {
                        state := sIdle
                        inputIndex := nextInputIndex
                    }
                }
            }
        }
    }
}

/* 
 * AXI4 demuxer with priority. A master with lower index has higher priority.
 */
class AXI4PriorityDemux(axi4Params: AXI4Params, masterModes: Seq[AXI4Mode], enableDebugMessage: Boolean = false) extends Module {
    val numberOfMasters = masterModes.length
    val io = IO(new Bundle {
        val in = MixedVec(masterModes.map(mode => Flipped(AXI4IO(axi4Params.asAXIMode(mode)))))
        val out = AXI4IO(axi4Params)
    })

    object DebugPrintf {
        def apply(p: Printable): Unit = {
            if(enableDebugMessage) {
                chiselPrintf(p)
            }
        }
    }
    val printf = DebugPrintf

    val inputIndexBits = log2Ceil(numberOfMasters + 1)
    val inputIndex = RegInit(numberOfMasters.U(inputIndexBits.W))   // Default: No input is selected.
    val addressBits = axi4Params.addressBits
    val maxBurstLength = axi4Params.maxBurstLength.get

    object State extends ChiselEnum {
        val sIdle, sReadTransfer, sWriteTransfer, sWriteResp= Value
    }
    val state = RegInit(State.sIdle)
    
    val ar = io.out.ar.get
    val r = io.out.r.get
    val count = RegInit(0.U(log2Ceil(maxBurstLength).W))
    val aw = io.out.aw.get
    val w = io.out.w.get
    val b = io.out.b.get

    val arValid = RegInit(false.B)
    val arReady = WireDefault(ar.ready)
    val arAddr = RegInit(0.U(addressBits.W))
    val arLen = RegInit(0.U(log2Ceil(maxBurstLength).W))
    ar.valid := arValid
    ar.bits.addr := arAddr
    ar.bits.len.get := arLen

    val rValid = WireDefault(r.valid)
    val rReady = WireDefault(false.B)
    val rData = WireDefault(r.bits.data)
    val rLast = WireDefault(r.bits.last.get)
    val rResp = WireDefault(r.bits.resp)
    r.ready := rReady
    
    val awValid = RegInit(false.B)
    val awReady = WireDefault(aw.ready)
    val awAddr = RegInit(0.U(addressBits.W))
    val awLen = RegInit(0.U(log2Ceil(maxBurstLength).W))
    aw.valid := awValid
    aw.bits.addr := awAddr
    aw.bits.len.get := awLen

    val wValid = WireDefault(false.B)
    val wBits = Wire(new AXI4W(axi4Params))
    val bReady = WireDefault(false.B)
    wBits.data := 0.U
    wBits.last match {
        case Some(last) => last := false.B
        case None => {}
    }
    wBits.strb := 0.U
    w.valid := wValid
    w.bits := wBits
    b.ready := bReady

    // Clear ARVALID if the last transaction completes.
    when(arValid && arReady) {
        arValid := false.B
    }
    // Clear AWVALID if the last transaction completes.
    when(awValid && awReady) {
        awValid := false.B
    }

    val hasReadRequest = io.in.map(port => port.ar.map(a => a.valid).getOrElse(false.B) ).reduce((l, r) => l || r)
    val hasWriteRequest = io.in.map(port => port.aw.map(a => a.valid).getOrElse(false.B) ).reduce((l, r) => l || r)
    val arIndex = PriorityEncoder(io.in.map(port => port.ar.map(a => a.valid).getOrElse(false.B)).toSeq)
    val awIndex = PriorityEncoder(io.in.map(port => port.aw.map(a => a.valid).getOrElse(false.B)).toSeq)
    
    for(masterIndex <- 0 to numberOfMasters - 1) {
        val mode = masterModes(masterIndex)
        val in = io.in(masterIndex)
        val selected = masterIndex.U === inputIndex
        val portArReady = WireDefault(false.B)
        val portAwReady = WireDefault(false.B)
        
        mode match {
            case AXI4ReadOnly => {}
            case _ => {
                in.aw.get.ready := portAwReady
                in.w.get.ready := selected && w.ready && state === State.sWriteTransfer
                in.b.get.valid := selected && b.valid && state === State.sWriteResp
                in.b.get.bits := b.bits

                when(state === State.sIdle && hasWriteRequest && awIndex === masterIndex.U && (!hasReadRequest || awIndex < arIndex)) {
                    inputIndex := masterIndex.U
                    when(!awValid) {
                        awValid := true.B
                        awAddr := in.aw.get.bits.addr
                        awLen := in.aw.get.bits.len.get
                        count := in.aw.get.bits.len.get
                    }
                    when(awReady) {
                        // Transit to sWriteTransfer state if the slave is ready.
                        state := State.sWriteTransfer
                        printf(p"[DEMUX] AW Select index=${masterIndex} addr=${Hexadecimal(in.aw.get.bits.addr)} len=${Hexadecimal(in.aw.get.bits.len.get)}\n")
                    }

                    portAwReady := awReady
                }
                when(selected) {
                    switch(state) {
                        is(State.sIdle) { }
                        is(State.sReadTransfer) { }
                        is(State.sWriteTransfer) {
                            wValid := in.w.get.valid
                            wBits := in.w.get.bits
                            when( in.w.get.valid && in.w.get.ready ) {
                                count := count - 1.U
                                when( count === 0.U ) {
                                    state := State.sWriteResp
                                }
                            }
                        }
                        is(State.sWriteResp) {
                            bReady := in.b.get.ready
                            when(in.b.get.valid && in.b.get.ready ) {
                                state := State.sIdle
                                inputIndex := numberOfMasters.U // invalidate inputIndex
                            }
                        }
                    }
                }
            }
        }

        
        mode match {
            case AXI4WriteOnly => {}
            case _ => {
                in.ar.get.ready := portArReady
                in.r.get.valid := selected && rValid && state === State.sReadTransfer
                in.r.get.bits := r.bits

                when(state === State.sIdle && hasReadRequest && arIndex === masterIndex.U && (!hasWriteRequest || arIndex <= awIndex)) {
                    inputIndex := masterIndex.U
                    when(!arValid) {
                        arValid := true.B
                        arAddr := in.ar.get.bits.addr
                        arLen := in.ar.get.bits.len.get
                    }
                    when(arReady) {
                        // Transit to sReadTransfer state if the slave is ready.
                        state := State.sReadTransfer
                        printf(p"[DEMUX] AR Select index=${masterIndex} addr=${Hexadecimal(in.ar.get.bits.addr)} len=${Hexadecimal(in.ar.get.bits.len.get)}\n")
                    }

                    portArReady := arReady
                }
                when(selected) {
                    switch(state) {
                        is(State.sIdle) { }
                        is(State.sReadTransfer) {
                            rReady := in.r.get.ready

                            when(rValid && rReady && rLast ) {
                                state := State.sIdle
                                inputIndex := numberOfMasters.U // invalidate inputIndex
                            }
                        }
                        is(State.sWriteTransfer) { }
                        is(State.sWriteResp) { }
                    }
                }
            }
        }
    }
}

