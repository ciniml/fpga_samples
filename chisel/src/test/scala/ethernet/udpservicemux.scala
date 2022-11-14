// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package ethernet

import chiseltest._
import chisel3.util._
import chisel3._
import chisel3.experimental.BundleLiterals._
import _root_.util._
import scala.util.control.Breaks
import scala.util.Random
import java.io._
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers
import chisel3.stage.PrintFullStackTraceAnnotation
import scala.util.Success
import scala.util.Failure

class UdpServiceMuxTestSystem() extends Module {
    val io = IO(new Bundle {
        val in = UdpServicePort(1)
        val gpioIn = Input(UInt(8.W))
        val gpioOut = Output(UInt(72.W))
    })
    val mux = Module(new UdpServiceMux(1, Seq(
          (context => context.destinationPort === 10000.U),
          (context => context.destinationPort === 10001.U),
        )))
    val loopback = Module(new UdpLoopback)
    loopback.io.port <> mux.io.servicePorts(0)
    val gpio = Module(new UdpGpio(numOutputBits = 72))
    gpio.io.port <> mux.io.servicePorts(1)
    gpio.io.gpioIn := io.gpioIn
    io.gpioOut := gpio.io.gpioOut
    io.in <> mux.io.in
}

class UdpServiceMuxTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "UdpServiceMux"
    behavior of dutName

    def checkResult(c: UdpServiceMuxTestSystem): Unit = {
        c.io.in.udpReceiveContext.initSource().setSourceClock(c.clock)
        c.io.in.udpReceiveData.initSource().setSourceClock(c.clock)
        c.io.in.udpSendContext.initSink().setSinkClock(c.clock)
        c.io.in.udpSendData.initSink().setSinkClock(c.clock)
        
        val random = new Random
        fork {
            c.io.in.udpReceiveContext.enqueue((new UdpContext).Lit(
                _.sourceMacAddress -> "x112233445566".U, _.sourceAddress -> "xc0a80101".U, _.sourcePort -> 54321.U,
                _.destinationMacAddress -> "xaabbccddeeff".U, _.destinationAddress -> "xc0a80102".U, _.destinationPort -> 10000.U,
                _.dataLength -> (1024 + 8).U
                ))
        } .fork {
            for(byte <- 0 to 1023) {
                c.io.in.udpReceiveData.enqueue(MultiByteSymbol(1).Lit(_.data -> (byte & 0xff).U, _.keep -> 1.U, _.last -> (byte == 1023).B))
            }
        } .fork {
            c.io.in.udpSendContext.expectDequeue((new UdpContext).Lit(
                _.sourceMacAddress -> "xaabbccddeeff".U, _.sourceAddress -> "xc0a80102".U, _.sourcePort -> 10000.U,
                _.destinationMacAddress -> "x112233445566".U, _.destinationAddress -> "xc0a80101".U, _.destinationPort -> 54321.U,
                _.dataLength -> (1024 + 8).U
                ))
        } .fork {
            for(byte <- 0 to 1023) {
                c.io.in.udpSendData.expectDequeue(MultiByteSymbol(1).Lit(_.data -> (byte & 0xff).U, _.keep -> 1.U, _.last -> (byte == 1023).B))
            }
        } .join()
    }

    def checkGpio(c: UdpServiceMuxTestSystem): Unit = {
        c.io.in.udpReceiveContext.initSource().setSourceClock(c.clock)
        c.io.in.udpReceiveData.initSource().setSourceClock(c.clock)
        c.io.in.udpSendContext.initSink().setSinkClock(c.clock)
        c.io.in.udpSendData.initSink().setSinkClock(c.clock)
        c.io.gpioIn.poke(0x5a)

        val random = new Random
        fork {
            c.io.in.udpReceiveContext.enqueue((new UdpContext).Lit(
                _.sourceMacAddress -> "x112233445566".U, _.sourceAddress -> "xc0a80101".U, _.sourcePort -> 54321.U,
                _.destinationMacAddress -> "xaabbccddeeff".U, _.destinationAddress -> "xc0a80102".U, _.destinationPort -> 10001.U,
                _.dataLength -> (1024 + 8).U
                ))
        } .fork {
            for(i <- 0 to 1023) {
                val byte = (if( i == 0 ) { 0xa5 } else { i }) & 0xff
                c.io.in.udpReceiveData.enqueue(MultiByteSymbol(1).Lit(_.data -> (byte & 0xff).U, _.keep -> 1.U, _.last -> (i == 1023).B))
            }
        } .fork {
            c.io.in.udpSendContext.expectDequeue((new UdpContext).Lit(
                _.sourceMacAddress -> "xaabbccddeeff".U, _.sourceAddress -> "xc0a80102".U, _.sourcePort -> 10001.U,
                _.destinationMacAddress -> "x112233445566".U, _.destinationAddress -> "xc0a80101".U, _.destinationPort -> 54321.U,
                _.dataLength -> (1 + 8).U
                ))
        } .fork {
            c.io.in.udpSendData.expectDequeue(MultiByteSymbol(1).Lit(_.data -> 0x5a.U, _.keep -> 1.U, _.last -> true.B))
        } .join()
        c.io.gpioOut.expect("x0807060504030201a5".U, "gpioOut must be the first 9 bytes of received data.")
    }

    val testAnnotations = Seq(PrintFullStackTraceAnnotation, VerilatorBackendAnnotation, WriteFstAnnotation)

    it should "run once" in {
        test(new UdpServiceMuxTestSystem).withAnnotations(testAnnotations) { c => checkResult(c) }
    }
    it should "run gpio" in {
        test(new UdpServiceMuxTestSystem).withAnnotations(testAnnotations) { c => checkGpio(c) }
    }
}
