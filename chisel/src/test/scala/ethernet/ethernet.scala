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

class EthernetServiceTester extends AnyFlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "EthernetService"
    behavior of dutName

    def runTest(c: EthernetService, inputFiles: Seq[String], outputFiles: Seq[String]): Unit = {
        val basePath = "chisel/src/test/scala/ethernet/data/"
        c.io.in.initSource().setSourceClock(c.clock)
        c.io.out.initSink().setSinkClock(c.clock)
        c.clock.setTimeout(1000)
        val random = new Random
        fork {
            outputFiles.foreach(outputFile => {
                val bis = new BufferedInputStream(new FileInputStream(basePath + outputFile))
                val rawOutput = bis.readAllBytes()
                val output = if( rawOutput.length < 64 ) {
                    rawOutput ++ Seq.fill(64 - rawOutput.length)(0.toByte)
                } else { rawOutput }
                (0 to output.length - 1).foreach(i => {
                    val byte = output(i) & 0xff
                    val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                    (0 to idleCycles - 1).foreach(i => {
                        c.clock.step(1)
                    })
                    println(f"byte: ${i}")
                    c.io.out.expectDequeue(MultiByteSymbol(1).Lit( _.data -> byte.U, _.keep -> 1.U, _.last -> (i == output.length - 1).B))
                })
            })
        } .fork {
            inputFiles.foreach(inputFile => {
                val bis = new BufferedInputStream(new FileInputStream(basePath + inputFile))
                val rawInput = bis.readAllBytes()
                val input = if( rawInput.length < 64 ) {
                    rawInput ++ Seq.fill(64 - rawInput.length)(0.toByte)
                } else { rawInput }
                (0 to input.length - 1).foreach(i => {
                    val byte = input(i) & 0xff
                    val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                    (0 to idleCycles - 1).foreach(i => {
                        c.clock.step(1)
                    })
                    c.io.in.enqueue(MultiByteSymbol(1).Lit( _.data -> byte.U, _.keep -> 1.U, _.last -> (i == input.length - 1).B))
                })
            })
        } .join()
    }

    val testEthernetServiceConfig = new EthernetServiceConfig(BigInt("AABBCCDDEEFF", 16), BigInt("c0a80402", 16))

    it should "run ARP single" in {
        test(new EthernetService(testEthernetServiceConfig)) { c => runTest(c, Seq("arp.input.bin"), Seq("arp.expected.bin")) }
    }
    it should "run ARP twice" in {
        test(new EthernetService(testEthernetServiceConfig)) { c => runTest(c, Seq("arp.input.bin", "arp.input.bin"), Seq("arp.expected.bin", "arp.expected.bin")) }
    }
    it should "run ICMP single" in {
        test(new EthernetService(testEthernetServiceConfig)) { c => runTest(c, Seq("icmp_dump.input.bin"), Seq("icmp_dump.expected.bin")) }
    }
}
