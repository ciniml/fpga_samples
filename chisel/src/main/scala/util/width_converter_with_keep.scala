// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import chisel3._
import chisel3.util._

case class WidthConverterWithKeep(inputWidth: Int, outputWidth: Int) extends Module {
    assert(inputWidth % 8 == 0)
    assert(outputWidth % 8 == 0)
    val inputWidthInBytes = inputWidth / 8
    val outputWidthInBytes = outputWidth / 8

    val io = IO(new Bundle {
        val enq = Flipped(new DecoupledIO(MultiByteSymbol(inputWidthInBytes)))
        val deq = new DecoupledIO(MultiByteSymbol(outputWidthInBytes))
    })

    val converters = (0 to 1).map(_ => Module(WidthConverterHalfWithKeep(inputWidth, outputWidth)))
    val inputCoreSelector = RegInit(0.U(1.W))   // Current selected core for input
    val outputCoreSelector = RegInit(0.U(1.W))  // Current selected core for output

    val inputCoreTransitToOutput = WireDefault(Mux(inputCoreSelector === 0.U, converters(0).io.transitToOutput, converters(1).io.transitToOutput))
    val outputCoreTransitToInput = WireDefault(Mux(outputCoreSelector === 0.U, converters(0).io.transitToInput, converters(1).io.transitToInput))
    
    // Connect cores and IOs
    for (phase <- 0 to 1) {
        converters(phase).io.enq.valid := io.enq.valid && (inputCoreSelector === phase.U)
        converters(phase).io.enq.bits := io.enq.bits
        converters(phase).io.deq.ready := io.deq.ready && (outputCoreSelector === phase.U)
    }

    io.enq.ready := Mux(inputCoreSelector === 0.U, converters(0).io.enq.ready, converters(1).io.enq.ready)
    io.deq.valid := Mux(outputCoreSelector === 0.U, converters(0).io.deq.valid, converters(1).io.deq.valid)
    io.deq.bits  := Mux(outputCoreSelector === 0.U, converters(0).io.deq.bits, converters(1).io.deq.bits)

    // Update core selection.
    when(inputCoreTransitToOutput) {   // The current input core will transit to the OUTPUT phase
        // Switch the input core
        inputCoreSelector := inputCoreSelector ^ 1.U
    }
    when(io.deq.valid && io.deq.ready && outputCoreTransitToInput) {   // The current output core will transit to the INPUT phase
        // Switch the output core
        outputCoreSelector := outputCoreSelector ^ 1.U
    }

}

case class WidthConverterHalfWithKeep(inputWidth: Int, outputWidth: Int) extends Module {
    val baseWidth = MathUtil.gcd(inputWidth, outputWidth)
    val bufferWidth = MathUtil.lcm(inputWidth, outputWidth).toInt
    val countPerInput = inputWidth/baseWidth
    val countPerOutput = outputWidth/baseWidth
    val maxCount = bufferWidth/baseWidth
    val counterWidth = log2Ceil(maxCount + 1)
    
    val maxInputCount = bufferWidth/inputWidth
    val maxOutputCount = bufferWidth/outputWidth
    val inputIndexWidth = log2Ceil(maxInputCount)
    val outputIndexWidth = log2Ceil(maxOutputCount)

    assert(inputWidth % 8 == 0)
    assert(outputWidth % 8 == 0)
    val inputWidthInBytes = inputWidth / 8
    val outputWidthInBytes = outputWidth / 8
    
    val io = IO(new Bundle {
        val enq = Flipped(new DecoupledIO(MultiByteSymbol(inputWidthInBytes)))
        val deq = new DecoupledIO(MultiByteSymbol(outputWidthInBytes))
        val transitToInput = Output(Bool())
        val transitToOutput = Output(Bool())
    })

    // width converter
    val buffer = Reg(Vec(maxInputCount, UInt(inputWidth.W)))
    val keep = Reg(Vec(maxInputCount, UInt(inputWidthInBytes.W)))
    val outputBuffer = Reg(UInt(outputWidth.W))
    val keepBuffer = Reg(UInt(outputWidthInBytes.W))
    val counter = RegInit(0.U(counterWidth.W))
    val inputIndex = RegInit(0.U(Math.max(inputIndexWidth, 1).W))
    val outputIndex = RegInit(0.U(Math.max(outputIndexWidth, 1).W))
    val phase = RegInit(false.B)
    val last = RegInit(false.B)
    val flush = RegInit(false.B)
    val valid = RegInit(false.B)
    val transitToInput = RegInit(false.B)
    val isLast = Wire(Bool())

    if( outputWidth >= inputWidth ) {
        isLast := counter < (countPerOutput*2).U
    } else {
        isLast := counter <= countPerOutput.U
    }

    when( valid && io.deq.ready ) {
        valid := false.B
        transitToInput := false.B
    }

    when( phase && (!valid || io.deq.ready) ) {
        if( maxInputCount > 0 ) {
            inputIndex := 0.U
        }
        
        if( maxCount > 1 ) {
            counter := counter - countPerOutput.U
        }
        if( maxOutputCount > 1 ) {
            outputIndex := Mux(outputIndex === (maxOutputCount - 1).U, 0.U, outputIndex + 1.U)
            phase := !isLast
            transitToInput := isLast
            last := isLast && flush
            (0 to maxOutputCount - 1).foreach(i => {
                when(outputIndex === i.U) {
                    outputBuffer := buffer.asUInt.apply((i+1)*outputWidth-1, i*outputWidth)
                    keepBuffer := keep.asUInt.apply((i+1)*outputWidthInBytes-1, i*outputWidthInBytes)
                }
            })
        } else {
            outputBuffer := buffer.asUInt
            keepBuffer := keep.asUInt
            last := flush
            phase := false.B
            transitToInput := true.B
        }
        (0 to maxInputCount - 1).foreach(i => {
            when(isLast) {
                buffer(i) := 0.U
                keep(i) := 0.U
            }
        })
        valid := true.B
    }
    io.transitToInput := transitToInput

    when(!phase && io.enq.valid && io.enq.ready ) {
        if( maxOutputCount > 1 ) {
            outputIndex := 0.U
        }
        if( maxCount > 1 ) {
            counter := counter + countPerInput.U
        }
        if( maxInputCount > 1 ) {
            inputIndex := Mux(inputIndex === (maxInputCount - 1).U, 0.U, inputIndex + 1.U)
            phase := counter === (maxCount - countPerInput).U || io.enq.bits.last
            flush := io.enq.bits.last
            (0 to maxInputCount - 1).foreach(i => {
                when(inputIndex === i.U) {
                    buffer(i) := io.enq.bits.data
                    keep(i) := io.enq.bits.keep
                }
            })
            //buffer := Cat(io.enq.bits.body, buffer(bufferWidth - 1, inputWidth))
        } else {
            phase := true.B
            flush := io.enq.bits.last
            buffer(0) := io.enq.bits.data
            keep(0) := io.enq.bits.keep
        }
    }
    io.transitToOutput := !phase && io.enq.valid && io.enq.ready && (if(maxInputCount > 1) counter === (maxCount - countPerInput).U || io.enq.bits.last else true.B)

    io.enq.ready := !phase
    io.deq.valid := valid
    io.deq.bits.data := outputBuffer
    io.deq.bits.keep := keepBuffer
    io.deq.bits.last := last
}
