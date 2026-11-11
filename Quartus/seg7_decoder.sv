`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: seg7_decoder
//
// Description: Decodes a 4-bit hex nibble (0-F) into DE1 7-segment display
//              segments. DE1's HEX displays are active-LOW: driving a
//              segment output to 0 turns it ON, 1 turns it OFF. `blank`
//              forces the display fully off (all segments 1), used when
//              a digit has nothing meaningful to show yet.
//
//              Segment bit order: seg_out = {g,f,e,d,c,b,a}
//////////////////////////////////////////////////////////////////////////////////

module seg7_decoder (
    input  logic [3:0] hex_in,
    input  logic        blank,
    output logic [6:0]  seg_out   // active-low: 0 = segment ON
);

    always_comb begin
        if (blank) begin
            seg_out = 7'b1111111;   // all segments off
        end else begin
            case (hex_in)
                4'h0: seg_out = 7'b1000000;
                4'h1: seg_out = 7'b1111001;
                4'h2: seg_out = 7'b0100100;
                4'h3: seg_out = 7'b0110000;
                4'h4: seg_out = 7'b0011001;
                4'h5: seg_out = 7'b0010010;
                4'h6: seg_out = 7'b0000010;
                4'h7: seg_out = 7'b1111000;
                4'h8: seg_out = 7'b0000000;
                4'h9: seg_out = 7'b0010000;
                4'hA: seg_out = 7'b0001000;
                4'hB: seg_out = 7'b0000011;
                4'hC: seg_out = 7'b1000110;
                4'hD: seg_out = 7'b0100001;
                4'hE: seg_out = 7'b0000110;
                4'hF: seg_out = 7'b0001110;
                default: seg_out = 7'b1111111;
            endcase
        end
    end

endmodule