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

class EthernetServiceTester extends AnyFlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "EthernetService"
    behavior of dutName

    val basePath = "chisel/src/test/scala/ethernet/data/"

    def writeAllBytes(path: String, data: Array[Byte]) = {
        scala.util.Using( new BufferedOutputStream(new FileOutputStream(basePath + path))) { bis =>
            bis.write(data)
        }
    }
    
    def runReceiveTestWithFiles(c: EthernetService, inputFiles: Seq[String], outputFiles: Option[Seq[String]], udpOutputFiles: Option[Seq[(String, UdpContext)]] = None): Unit = {
        def readAllBytes(path: String): Array[Byte] = {
            val result = scala.util.Using( new BufferedInputStream(new FileInputStream(basePath + path))) { bis =>
                bis.readAllBytes()
            }
            result match {
                case Success(bytes) => bytes
                case Failure(_) => new Array(0)
            }
        }
        val inputPackets = inputFiles.map(readAllBytes)
        val outputPackets = outputFiles.map(files => files.map(readAllBytes))
        val udpOutputPackets = udpOutputFiles.map(files => files.map { case (file, udpContext) => (readAllBytes(file), udpContext)} )

        runReceiveTest(c, inputPackets, outputPackets, udpOutputPackets)
    }

    def ensureMinimumPacketLength(packet: Array[Byte]): Array[Byte] = {
        if( packet.length < 64 ) {
            packet ++ Seq.fill(64 - packet.length)(0.toByte)
        } else { 
            packet 
        }
    }

    def runReceiveTest(c: EthernetService, inputPackets: Seq[Array[Byte]], outputPackets: Option[Seq[Array[Byte]]], udpOutputPackets: Option[Seq[(Array[Byte], UdpContext)]]): Unit = {
        c.io.in.initSource().setSourceClock(c.clock)
        c.io.out.initSink().setSinkClock(c.clock)
        c.io.udpSendContext.initSource().setSinkClock(c.clock)
        c.io.udpSendData.initSource().setSinkClock(c.clock)
        c.io.udpReceiveContext.initSink().setSinkClock(c.clock)
        c.io.udpReceiveData.initSink().setSinkClock(c.clock)
        c.clock.setTimeout(1000)
        val random = new Random
        fork {
            outputPackets match {
                case Some(outputPackets) => {
                    outputPackets.map(ensureMinimumPacketLength).foreach(outputPacket => {
                        (0 to outputPacket.length - 1).foreach(i => {
                            val byte = outputPacket(i) & 0xff
                            val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                            (0 to idleCycles - 1).foreach(i => {
                                c.clock.step(1)
                            })
                            println(f"byte: ${i}")
                            c.io.out.expectDequeue(MultiByteSymbol(1).Lit( _.data -> byte.U, _.keep -> 1.U, _.last -> (i == outputPacket.length - 1).B))
                        })
                    })
                }
                case None => {}
            }
        } .fork {
            inputPackets.map(ensureMinimumPacketLength).foreach(inputPacket => {
                (0 to inputPacket.length - 1).foreach(i => {
                    val byte = inputPacket(i) & 0xff
                    val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                    (0 to idleCycles - 1).foreach(i => {
                        c.clock.step(1)
                    })
                    c.io.in.enqueue(MultiByteSymbol(1).Lit( _.data -> byte.U, _.keep -> 1.U, _.last -> (i == inputPacket.length - 1).B))
                })
            })
        } .fork {
            udpOutputPackets match {
                case Some(udpOutputPackets) => {
                    udpOutputPackets.foreach { case (udpPacket, _) => {
                        (0 to udpPacket.length - 1).foreach(i => {
                            val byte = udpPacket(i) & 0xff
                            val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                            (0 to idleCycles - 1).foreach(i => {
                                c.clock.step(1)
                            })
                            c.io.udpReceiveData.expectDequeue(MultiByteSymbol(1).Lit( _.data -> byte.U, _.keep -> 1.U, _.last -> (i == udpPacket.length - 1).B))
                        })
                    }}
                }
                case None => {}
            }
        } .fork {
            udpOutputPackets match {
                case Some(udpOutputPackets) => {
                    udpOutputPackets.foreach { case (_, udpContext) => {
                        c.io.udpReceiveContext.expectDequeue(udpContext)
                    }}
                }
                case None => {}
            }
        } .join()
    }

    def runUDPSendTest(c: EthernetService, udpInputPackets: Seq[(Array[Byte], UdpContext)], outputPackets: Seq[Array[Byte]] ): Unit = {
        c.io.in.initSource().setSourceClock(c.clock)
        c.io.out.initSink().setSinkClock(c.clock)
        c.io.udpSendContext.initSource().setSourceClock(c.clock)
        c.io.udpSendData.initSource().setSourceClock(c.clock)
        c.io.udpReceiveContext.initSink().setSinkClock(c.clock)
        c.io.udpReceiveData.initSink().setSinkClock(c.clock)
        c.clock.setTimeout(1000)
        val random = new Random
        fork {
            outputPackets.map(ensureMinimumPacketLength).foreach(outputPacket => {
                (0 to outputPacket.length - 1).foreach(i => {
                    val byte = outputPacket(i) & 0xff
                    val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                    (0 to idleCycles - 1).foreach(i => {
                        c.clock.step(1)
                    })
                    println(f"byte: ${i}, ${byte}")
                    c.io.out.expectDequeue(MultiByteSymbol(1).Lit( _.data -> byte.U, _.keep -> 1.U, _.last -> (i == outputPacket.length - 1).B))
                })
            })
        }  .fork {
            udpInputPackets.foreach { case (udpPacket, _) => {
                (0 to udpPacket.length - 1).foreach(i => {
                    val byte = udpPacket(i) & 0xff
                    val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                    (0 to idleCycles - 1).foreach(i => {
                        c.clock.step(1)
                    })
                    c.io.udpSendData.enqueue(MultiByteSymbol(1).Lit( _.data -> byte.U, _.keep -> 1.U, _.last -> (i == udpPacket.length - 1).B))
                })
            }}
        } .fork {
            udpInputPackets.foreach { case (_, udpContext) => {
                c.io.udpSendContext.enqueue(udpContext)
            }}
        } .join()
    }

    val testEthernetServiceConfig = new EthernetServiceConfig(BigInt("AABBCCDDEEFF", 16), BigInt("c0a80402", 16))
    val udpEthernetServiceConfig = new EthernetServiceConfig(BigInt("30aea4cad504", 16), BigInt("c0a81451", 16))

    it should "run ARP single" in {
        test(new EthernetService(testEthernetServiceConfig)).withAnnotations(Seq(PrintFullStackTraceAnnotation, VerilatorBackendAnnotation)) { c => runReceiveTestWithFiles(c, Seq("arp.input.bin"), Some(Seq("arp.expected.bin"))) }
    }
    it should "run ARP twice" in {
        test(new EthernetService(testEthernetServiceConfig)).withAnnotations(Seq(PrintFullStackTraceAnnotation, VerilatorBackendAnnotation)) { c => runReceiveTestWithFiles(c, Seq("arp.input.bin", "arp.input.bin"), Some(Seq("arp.expected.bin", "arp.expected.bin"))) }
    }
    it should "run ICMP single" in {
        test(new EthernetService(testEthernetServiceConfig)).withAnnotations(Seq(PrintFullStackTraceAnnotation, VerilatorBackendAnnotation)) { c => runReceiveTestWithFiles(c, Seq("icmp_dump.input.bin"), Some(Seq("icmp_dump.expected.bin"))) }
    }
    it should "run UDP single" in {
        test(new EthernetService(udpEthernetServiceConfig)).withAnnotations(Seq(PrintFullStackTraceAnnotation, VerilatorBackendAnnotation)) { c => runReceiveTestWithFiles(c, Seq("udp.input.bin"), None, 
                Some(Seq(("udp.output.bin", (new UdpContext).Lit(_.dataLength -> (8 + 1024).U, _.destinationMacAddress -> "x30aea4cad504".U, _.destinationAddress -> "xc0a81451".U, _.destinationPort -> 54280.U, _.sourceMacAddress -> "xa0595042a6fd".U, _.sourceAddress -> "xc0a81401".U, _.sourcePort -> 10000.U))))) }
    }

    val udpSendTestPayload = (0 to 1023).map(n => (n & 0xff).toByte).toArray
    val udpSendTestUdpDataLength = UdpHeader.length + udpSendTestPayload.length
    val udpSendTestTotalLength = 20 + udpSendTestUdpDataLength
    val udpSendTestContext = (new UdpContext).Lit(
            _.dataLength -> udpSendTestUdpDataLength.U, 
            _.destinationMacAddress -> "xa0595042a6fd".U, _.destinationAddress -> "xc0a81401".U, _.destinationPort -> 10000.U, 
            _.sourceMacAddress -> "x30aea4cad504".U, _.sourceAddress -> "xc0a81451".U, _.sourcePort -> 54280.U)
    
    val udpSendTestExpectedEthernetHeaer = Seq(
        // Ethernet 
        0xa0, 0x59, 0x50, 0x42, 0xa6, 0xfd, // Destination
        0x30, 0xae, 0xa4, 0xca, 0xd5, 0x04, // Source
        0x08, 0x00,                         // Type = IPv4
    ).map(n => n.toByte)
    val udpSendTestExpectedIpHeader = Seq(
        // IPv4
        0x45, 0x00, udpSendTestTotalLength >> 8, udpSendTestTotalLength & 0xff,     // Version = 4, header length = 5, total length
        0x12, 0x34, 0x40, 0x00,             // identification, flags_and_offset
        0xff, 0x11, 0x00, 0x00,             // TTL, protocol, checksum
        0xc0, 0xa8, 0x14, 0x51,             // source address
        0xc0, 0xa8, 0x14, 0x01,             // destination address
    ).map(n => n.toByte)
    val udpSendTestExpectedUdpHeader = Seq(
        // UDP
        0xd4, 0x08, 0x27, 0x10,             // source port = 54280, dest = 10000
        udpSendTestUdpDataLength >> 8, udpSendTestUdpDataLength & 0xff,   // data length
        0x00, 0x00,                         // checksum
    ).map(n => n.toByte)
    val ipv4Checksum = udpSendTestExpectedIpHeader.zipWithIndex.map { case (n, i) => ((n & 0xff) << (((i + 1) % 2) * 8)) & 0xffff }.foldLeft(0) { case (l, r) => {
        val result = l + r
        if( (result & 0x7fff0000) != 0 ) {
            (result + 1) & 0xffff
        } else {
            result & 0xffff
        }
    }} ^ 0xffff
    val udpSendTestExpectedIpHeaderWithChecksum = udpSendTestExpectedIpHeader.take(10) ++ Seq(ipv4Checksum >> 8, ipv4Checksum & 0xff).map(n => n.toByte) ++ udpSendTestExpectedIpHeader.drop(12)
    val udpSendTestExpectedOutput = (udpSendTestExpectedEthernetHeaer ++ udpSendTestExpectedIpHeaderWithChecksum ++ udpSendTestExpectedUdpHeader ++ udpSendTestPayload).toArray

    println(f"checksum: ${ipv4Checksum.toHexString}")
    it should "run Send UDP single" in {
        test(new EthernetService(udpEthernetServiceConfig)).withAnnotations(Seq(PrintFullStackTraceAnnotation, VerilatorBackendAnnotation, WriteFstAnnotation)) { c => runUDPSendTest(c, Seq((udpSendTestPayload, udpSendTestContext)), Seq(udpSendTestExpectedOutput)) }
    }
}

