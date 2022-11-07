// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package ethernet

import org.scalatest._
import chiseltest._
import chisel3.util._
import chisel3._
import chisel3.experimental.BundleLiterals._
import _root_.util._
import scala.util.control.Breaks
import scala.util.Random
import java.io._

class EthernetServiceTester extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "UartSystem"
    behavior of dutName

    def runTest(c: EthernetService, inputFiles: Seq[String], outputFiles: Seq[String]): Unit = {
        
        c.io.in.initSource().setSourceClock(c.clock)
        c.io.out.initSink().setSinkClock(c.clock)
        val random = new Random
        fork {
            outputFiles.foreach(outputFile => {
                val bis = new BufferedInputStream(new FileInputStream(outputFile))
                val output = bis.readAllBytes()
                (0 to output.length).foreach(i => {
                    val byte = output(i)
                    val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                    (0 to idleCycles - 1).foreach(i => {
                        c.clock.step(1)
                    })
                    c.io.out.expectDequeue(MultiByteSymbol(1).Lit( _.data -> byte.U, _.keep -> 1.U, _.last -> (i == output.length - 1).B))
                })
            })
        } .fork {
            inputFiles.foreach(inputFile => {
                val bis = new BufferedInputStream(new FileInputStream(inputFile))
                val input = bis.readAllBytes()
                (0 to input.length).foreach(i => {
                    val byte = input(i)
                    val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                    (0 to idleCycles - 1).foreach(i => {
                        c.clock.step(1)
                    })
                    c.io.in.enqueue(MultiByteSymbol(1).Lit( _.data -> byte.U, _.keep -> 1.U, _.last -> (i == input.length - 1).B))
                })
            })
        } .join()
    }

    it should "simple" in {
        test(new EthernetService) { c => runTest(c, Seq("input.bin"), Seq("output.bin")) }
    }
}
