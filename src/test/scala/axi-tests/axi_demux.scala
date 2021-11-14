// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package axi

import org.scalatest._
import chiseltest._
import chisel3._
import chisel3.util._
import chisel3.util.random.LFSRReduce


class AXITrafficSource(axiParams: AXI4Params, fromAddress: BigInt, toAddressInclusive: BigInt, burstLength: Int) extends Module {
    val io = IO(new Bundle{
        val axi = AXI4IO(axiParams)
        val fail = Output(Bool())
        val done = Output(Bool())
    })

    val fail = RegInit(false.B)
    io.fail := fail
    val done = WireDefault(false.B)
    io.done := done

    val burstBytes = (burstLength * axiParams.dataBits / 8)
    val bytesToTransfer = (toAddressInclusive - fromAddress + 1)
    axiParams.mode match {
        case AXI4ReadOnly => {}
        case _ => {
            val aw = io.axi.aw.get
            val w = io.axi.w.get
            val b = io.axi.b.get

            val address = RegInit(0.U(axiParams.addressBits.W))
            
            val awValid = RegInit(false.B)
            aw.valid := awValid
            val awReady = WireDefault(aw.ready)
            val awAddr = RegInit(0.U(axiParams.addressBits.W))

            aw.bits.addr := awAddr
            aw.bits.len.get := (burstLength - 1).U

            val data = RegInit(0.U(axiParams.dataBits.W))
            val bytesTransferred = RegInit(0.U(log2Ceil(bytesToTransfer + 1).W))
            val burstCount = RegInit(0.U(log2Ceil(burstLength).W))
            val wValid = RegInit(false.B)
            val wReady = WireDefault(w.ready)
            val wData = RegInit(0.U(axiParams.dataBits.W))
            val wLast = RegInit(false.B)
            w.valid := wValid
            w.bits.data := wData
            w.bits.last.get := wLast
            w.bits.strb := ((1 << (axiParams.dataBits / 8)) - 1).U

            val inTransaction = RegInit(false.B)

            b.ready := random.LFSR(16).xorR()

            when(awValid && awReady) {
                awValid := false.B
            }
            when(wValid && wReady) {
                wValid := false.B
            }

            when( !inTransaction ) {
                when((!awValid || awReady) && address <= toAddressInclusive.U) {
                    printf(p"[${Hexadecimal(address)}] issue AW
")
                    awValid := true.B
                    awAddr := address
                    address := address + burstBytes.U
                    inTransaction := true.B
                    burstCount := 0.U
                }
            } .otherwise {
                when((!wValid || wReady) && bytesTransferred < bytesToTransfer.U && random.LFSR(4).xorR()) {
                    printf(p"[${Hexadecimal(awAddr)}] issue W beat=${burstCount}
")
                    val isLast = burstCount === (burstLength - 1).U
                    wValid := true.B
                    wLast := isLast
                    wData := data
                    burstCount := burstCount + 1.U
                    data := data + 1.U
                    inTransaction := !isLast
                    bytesTransferred := bytesTransferred + (axiParams.dataBits / 8).U
                }
            }
            done := bytesTransferred === bytesToTransfer.U
            val prevDone = RegNext(done, false.B)
            when(!prevDone && done) {
                printf(p"DONE
")
            }
        }
    }
}

class AXITrafficSink(axiParams: AXI4Params) extends Module {
    val io = IO(new Bundle{
        val axi = Flipped(AXI4IO(axiParams))
        val fail = Output(Bool())
    })

    val fail = WireDefault(false.B)
    io.fail := fail

    axiParams.mode match {
        case AXI4ReadOnly => {}
        case _ => {
            val aw = io.axi.aw.get
            val w = io.axi.w.get
            val b = io.axi.b.get

            val awValid = WireDefault(aw.valid)
            val awReady = WireDefault(false.B)
            aw.ready := awReady
            val wValid = WireDefault(w.valid)
            val wReady = WireDefault(false.B)
            w.ready := wReady
            val bValid = WireDefault(false.B)
            val bReady = WireDefault(b.ready)
            b.valid := bValid
            b.bits.resp := AXI4Resp.OKAY

            val address = RegInit(0.U(axiParams.addressBits.W))
            val count = RegInit(0.U(log2Ceil(axiParams.maxBurstLength.get).W))
            val sIdle :: sData :: sResp :: sError :: Nil = Enum(4)
            val state = RegInit(sIdle)
            switch(state) {
                is( sIdle ) {
                    awReady := random.LFSR(8).xorR()
                    when(awValid && awReady) {
                        printf(p"[${Hexadecimal(address)}] AW addr=${Hexadecimal(aw.bits.addr)} len=${Hexadecimal(aw.bits.len.get)}
")

                        address := aw.bits.addr
                        count := aw.bits.len.get
                        state := sData
                    } 
                }
                is( sData ) {
                    wReady := random.LFSR(8).xorR()
                    when(wValid && wReady) {
                        count := count - 1.U
                        address := address + (axiParams.dataBits/8).U
                        when(count === 0.U) {
                            state := sResp
                        }
                        // Check
                        val wLastExpected = count === 0.U
                        when( wLastExpected =/= w.bits.last.get ) {
                            printf(p"[${Hexadecimal(address)}] WLAST mismatch expected: ${wLastExpected} actual: ${w.bits.last.get}")
                            state := sError
                        }
                        val wDataExpected = address / (axiParams.dataBits/8).U
                        when( w.bits.data =/= wDataExpected ) {
                            printf(p"[${Hexadecimal(address)}] WDATA mismatch expected: ${Hexadecimal(wDataExpected)} actual: ${Hexadecimal(w.bits.data)}
")
                            state := sError
                        }
                    }
                }
                is( sResp ) {
                    bValid := true.B
                    when(bValid && bReady) {
                        state := sIdle
                    }
                }
                is( sError ) {
                    fail := true.B
                }
            }
        }
    }
}

class AXI4DemuxTestSystem extends Module {
    val io = IO(new Bundle {
        val finish = Output(Bool())
        val fail = Output(Bool())
    })

    val params = AXI4Params(32, 32, AXI4WriteOnly, Some(9))
    val demux = Module(new AXI4Demux(params, 2))
    val sink = Module(new AXITrafficSink(params))
    val source1 = Module(new AXITrafficSource(params, 0x0000, 0x0fff, 4))
    val source2 = Module(new AXITrafficSource(params, 0x0000, 0x1fff, 8))
    val source1Error = WireDefault(false.B)
    val source2Error = WireDefault(false.B)

    demux.io.in(0) <> AXIProtocolChecker(source1.io.axi, Some(source1Error))
    demux.io.in(1) <> AXIProtocolChecker(source2.io.axi, Some(source2Error))
    demux.io.out <> sink.io.axi

    io.fail := source1.io.fail || source2.io.fail || sink.io.fail || source1Error || source2Error
    io.finish := source1.io.done && source2.io.done
}

class AXI4DemuxTest
    extends FlatSpec
    with ChiselScalatestTester
    with Matchers {
  val dutName = "AXI4Demux"
  behavior of dutName

  it should "simple" in {
    test(new AXI4DemuxTestSystem) { c =>
      c.clock.setTimeout(0x2000*4)
      
      while( !c.io.finish.peek().litToBoolean ) {
        c.io.fail.expect(false.B, "Result check failed")
        c.clock.step()
      }
    }
  }
}
