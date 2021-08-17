package uart

import chisel3._
import chisel3.util._

class UartTx(numberOfBits: Int, baudDivider: Int) extends Module {
    val io = IO(new Bundle{
        val in = Flipped(Decoupled(UInt(numberOfBits.W)))
        val tx = Output(Bool())
    })

    val rateCounter = RegInit(0.U(log2Ceil(baudDivider).W))
    val bitCounter = RegInit(0.U(log2Ceil(numberOfBits + 2).W))
    val bits = Reg(UInt((numberOfBits + 2).W))

    when(rateCounter === 0.U) {
        when( bitCounter > 0.U ) {
            io.tx := bits(0)
            
            bitCounter := bitCounter - 1.U
        }
        rateCounter := (baudDivider - 1).U
    } .otherwise {
        rateCounter := rateCounter - 1.U
    }
}