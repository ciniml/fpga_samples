package sound

import chisel3._
import chisel3.util._

class I2sMaster(val numberOfBitsPerChannel: Int, val numberOfCyclesPerChannel: Int, val defaultValue: BigInt) extends Module {
    if( numberOfBitsPerChannel > numberOfCyclesPerChannel) {
        throw new IllegalArgumentException("numberOfBitsPerChannel must be less than or equal to numberOfCyclesPerChannel")
    }

    val io = IO(new Bundle {
        val clockEnable = Input(Bool())
        val dataIn = Flipped(Irrevocable(UInt((numberOfBitsPerChannel * 2).W)))
        val wordSelect = Output(Bool())
        val dataOut = Output(Bool())
    })

    val data = RegInit(((defaultValue << numberOfBitsPerChannel) | defaultValue).U((numberOfBitsPerChannel*2).W))
    val wordSelect = RegInit(true.B)
    val dataOut = RegInit(false.B)
    val counter = RegInit(0.U(log2Ceil(numberOfCyclesPerChannel).W))

    val nextDataIn = Mux(io.dataIn.valid, io.dataIn.bits, Fill(2, defaultValue.U(numberOfBitsPerChannel.W)))
    val nextDataOut = data(numberOfBitsPerChannel * 2 - 1)
    
    io.dataIn.ready := counter === 1.U && wordSelect && io.clockEnable
    io.wordSelect := wordSelect
    io.dataOut := dataOut
    
    when( io.clockEnable ) {
        when( io.dataIn.ready ) {
            printf(p"counter: ${counter} set:   ${Hexadecimal(nextDataIn)} out: ${nextDataOut}\n")
            data := nextDataIn
        } .elsewhen( (numberOfBitsPerChannel == numberOfCyclesPerChannel).B || (0.U < counter && counter <= numberOfBitsPerChannel.U) ) {
            printf(p"counter: ${counter} shift: ${Hexadecimal(data << 1)} out: ${nextDataOut}\n")
            data := data << 1
        }

        dataOut := data(numberOfBitsPerChannel * 2 - 1)

        when( counter === 0.U ) {
            wordSelect := !wordSelect
            counter := (numberOfCyclesPerChannel - 1).U
        } .otherwise {
            counter := counter - 1.U
        }
    }
}