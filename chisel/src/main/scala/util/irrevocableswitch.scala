// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import chisel3._
import chisel3.util._
import chisel3.internal.naming.chiselName
import chisel3.experimental.ChiselEnum


@chiselName
class IrrevocableUnsafeMux[T <: Data](val gen: T, val n: Int) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(Vec(n, Irrevocable(gen)))
        val out = Irrevocable(gen)
        val select = Input(UInt(log2Ceil(n + 1).W)) // Select channel. disable all channels if select == n.
    })

    val valid = WireDefault(false.B)
    val bits = WireDefault(io.in(0).bits)
    io.out.valid := valid
    io.out.bits := bits
    
    for(i <- 0 to n - 1) {
        val ready = WireDefault(false.B)
        io.in(i).ready := ready
        when(i.U === io.select) {
            valid := io.in(i).valid
            bits := io.in(i).bits
            ready := io.out.ready
        }
    }
}

@chiselName
class IrrevocableUnsafeDemux[T <: Data](val gen: T, val n: Int) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(Irrevocable(gen))
        val out = Vec(n, Irrevocable(gen))
        val select = Input(UInt(log2Ceil(n + 1).W)) // Select channel. disable all channels if select == n.
    })

    val ready = WireDefault(false.B)
    io.in.ready := ready
    
    for(i <- 0 to n - 1) {
        io.out(i).valid := i.U === io.select && io.in.valid
        io.out(i).bits := io.in.bits
        when(i.U === io.select) {
            ready := io.out(i).ready
        }
    }
}


@chiselName
class IrrevocableMux[T <: Data](val gen: T, val n: Int) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(Vec(n, Irrevocable(gen)))
        val out = Irrevocable(gen)
        val select = Input(UInt(log2Ceil(n + 1).W)) // Select channel. disable all channels if select == n.
    })

    val data = Reg(gen)
    val valid = RegInit(false.B)
    val ready = WireDefault(io.out.ready)
    io.out.bits := data
    io.out.valid := valid

    when(valid && ready) {
        valid := false.B
    }

    for(i <- 0 to n - 1) {
        io.in(i).ready := io.select === i.U && (!valid || ready)
        when( io.in(i).valid && io.in(i).ready ) {
            valid := true.B
            data := io.in(i).bits
        }
    }
}


@chiselName
class IrrevocableDemux[T <: Data](val gen: T, val n: Int) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(Irrevocable(gen))
        val out = Vec(n, Irrevocable(gen))
        val select = Input(UInt(log2Ceil(n + 1).W)) // Select channel. disable all channels if select == n.
    })

    val ready = WireDefault(false.B)
    io.in.ready := ready
    
    for(i <- 0 to n - 1) {
        val data = Reg(gen)
        val valid = RegInit(false.B)
        io.out(i).valid := valid
        io.out(i).bits := data
        when(valid && io.out(i).ready) {
            valid := false.B
        }
        when(io.select === i.U) {
            ready := io.out(i).ready
            when( io.in.valid && io.in.ready ) {
                valid := true.B
                data := io.in.bits
            }
        }
    }
}


@chiselName
class IrrevocableBroadcaster[T <: Data](val gen: T, val n: Int) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(Irrevocable(gen))
        val out = Vec(n, Irrevocable(gen))
    })

    val validAny = Wire(Bool())
    val readyAll = Wire(Bool())
    val valids = RegInit(VecInit((0 to n-1).map(_ => false.B)))
    val bits = Reg(gen)
    
    for(i <- 0 to n - 1) {
        when(io.out(i).valid && io.out(i).ready) {
            valids(i) := false.B
        }
    }
    when(io.in.valid && io.in.ready) {
        (0 to n-1).foreach(i => valids(i) := true.B)
        bits := io.in.bits
    }
    io.in.ready := !validAny || readyAll

    validAny := (0 to n - 1).map(i => io.out(i).valid).reduceLeft((l, r) => l || r)
    readyAll := (0 to n - 1).map(i => io.out(i).ready).reduceLeft((l, r) => l && r)
    for(i <- 0 to n - 1) {
        io.out(i).valid := valids(i)
        io.out(i).bits := bits    
    }
}

class CountingIrrevocableSwitchCommand(val n: Int, val maxCount: Int) extends Bundle {
    val selectBits = log2Ceil(n)
    val countBits = log2Ceil(maxCount + 1)

    val select = UInt(selectBits.W)
    val count = UInt(countBits.W)
}
object CountingIrrevocableSwitchCommand {
    def apply(n: Int, maxCount: Int): CountingIrrevocableSwitchCommand = {
        new CountingIrrevocableSwitchCommand(n, maxCount)
    }
}

@chiselName
class CountingIrrevocableMux[T <: Data](val gen: T, val n: Int, val maxCount: Int) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(Vec(n, Irrevocable(gen)))
        val out = Irrevocable(gen)
        val selectCommand = Flipped(Irrevocable(CountingIrrevocableSwitchCommand(n, maxCount)))
    })

    val mux = Module(new IrrevocableMux(gen, n))
    io.in <> mux.io.in
    io.out <> mux.io.out

    val select = RegInit(0.U(log2Ceil(n).W))
    val inputCount = RegInit(0.U(log2Ceil(maxCount + 1).W))
    val outputCount = RegInit(0.U(log2Ceil(maxCount + 1).W))

    object State extends ChiselEnum {
      val sIdle, sProcessing = Value
    }
    val state = RegInit(State.sIdle)

    val selectCommandValid = io.selectCommand.valid
    val selectCommandReady = Wire(Bool())
    io.selectCommand.ready := selectCommandReady
    val selectCommand = io.selectCommand.bits

    selectCommandReady := state === State.sIdle
    mux.io.select := Mux(inputCount === 0.U, n.U, select)
    switch(state) {
        is(State.sIdle) {
            when(selectCommandValid && selectCommandReady) {
                when( selectCommand.count > 0.U ) {
                    select := selectCommand.select
                    inputCount := selectCommand.count
                    outputCount := selectCommand.count
                    state := State.sProcessing
                }
            }
        }
        is(State.sProcessing) {
            for(i <- 0 to n - 1) {
                when(select === i.U && io.in(i).valid && io.in(i).ready) {
                    when(inputCount > 0.U) {
                        inputCount := inputCount - 1.U
                    }
                }
                when(select === i.U && io.out.valid && io.out.ready) {
                    when(outputCount > 0.U) {
                        outputCount := outputCount - 1.U
                    }
                }
            }
            when(inputCount === 0.U && outputCount === 0.U) {
                state := State.sIdle
            }
        }
    }
}


@chiselName
class CountingIrrevocableDemux[T <: Data](val gen: T, val n: Int, val maxCount: Int) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(Irrevocable(gen))
        val out = Vec(n, Irrevocable(gen))
        val selectCommand = Flipped(Irrevocable(CountingIrrevocableSwitchCommand(n, maxCount)))
    })

    val demux = Module(new IrrevocableDemux(gen, n))
    io.in <> demux.io.in
    io.out <> demux.io.out

    val select = RegInit(0.U(log2Ceil(n).W))
    val count = RegInit(0.U(log2Ceil(maxCount + 1).W))

    object State extends ChiselEnum {
      val sIdle, sProcessing = Value
    }
    val state = RegInit(State.sIdle)

    val selectCommandValid = io.selectCommand.valid
    val selectCommandReady = Wire(Bool())
    io.selectCommand.ready := selectCommandReady
    val selectCommand = io.selectCommand.bits

    selectCommandReady := state === State.sIdle
    demux.io.select := Mux(state === State.sIdle, n.U, select)
    switch(state) {
        is(State.sIdle) {
            when(selectCommandValid && selectCommandReady) {
                when( selectCommand.count > 0.U ) {
                    select := selectCommand.select
                    count := selectCommand.count
                    state := State.sProcessing
                }
            }
        }
        is(State.sProcessing) {
            when(io.in.valid && io.in.ready) {
                count := count - 1.U
                when(count === 1.U) {
                    state := State.sIdle
                }
            }
        }
    }
}
