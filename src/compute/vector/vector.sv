/**

    Vector Module
        - I/O Processor
          External Interface can access Internal A/B/C Bram
        - Scheduler
          Read data from A/B BRAM, and put it in core. And scheduler transfer Result of core into Scratchpad C
          Scheduler must provide Computing Information such as Accumulate, Operator, and so on
          so scheduler works like Mini Processor, or Command issuer
        - Vector Core
          Vector Core consist with ALU, Reduce Unit (for Reducing Operator such as Softmax) but work in order
        
        - ALU (All the operator can support Accumulate)
          * Multi Lane Out Operators *
          Add
          Sub
          Mul
          And
          Or
          Xor
          Shift
          Max
          Min
          Exp
          Sqrt

          * Single Lane Out Operators *
          Max
          Min
          Sum
          Dot

**/


module vector();

endmodule