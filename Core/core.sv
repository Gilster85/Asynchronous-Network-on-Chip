`timescale 1ns/100ps
import SystemVerilogCSP::*;

module core (interface dg_8b, interface db_8b, interface data_out_11b, interface data_control_out, interface data_in_11b);
    parameter FL = 2;
	parameter BL = 2;  logic [WIDTH-1:0] SendValue=0;
	logic select=0;
	logic [10:0] router_data;
	logic [7:0] dg_data;
	logic [7:0] db_data;
	logic [10:0] output_data;
	logic [1:0] control = 1;
	logic [6:0] raw_data;
	
	task calc_parity(input [7:0] data, output [10:0] data_out);
		// Take input 8-bit data, and output 11-bit data including IP, data and parity bits
		// Calculate and combine parity bits in output
		logic [10:0] in_data;
		in_data[3:0] = data[3:0];
		in_data[6] = data[4];
		in_data[8] = data[5];
		in_data[9] = data[6];
		in_data[10] = data[7];
		in_data[4] = in_data[6] ^ in_data[8] ^ in_data[10];
		in_data[5] = in_data[6] ^ in_data[9] ^ in_data[10];
		in_data[7] = in_data[8] ^ in_data[9] ^ in_data[10];
		data_out = in_data;	
	endtask

	task hamming_fix(ref [6:0] raw_data_ref);
		logic P1;
		logic P2;
		logic P4;
		logic [2:0] parity_bit;
		// Parse the data from the router. The format is : | 4-bit IP | 7-bit data |
		//		data section has a format of: | P1 P2 D1 P3 D2 D3 D4 |
		// Check parity and fix data bits
		P1 = 0;
		P2 = 0;
		P4 = 0;
		parity_bit = 0;
		P1 = raw_data_ref[0] ^ raw_data_ref[2] ^ raw_data_ref[4] ^ raw_data_ref[6];
		P2 = raw_data_ref[1] ^ raw_data_ref[2] ^ raw_data_ref[5] ^ raw_data_ref[6];
		P4 = raw_data_ref[3] ^ raw_data_ref[4] ^ raw_data_ref[5] ^ raw_data_ref[6];
		if (P1 == 1)
		begin
			parity_bit = parity_bit + 1;
		end
		if (P2 == 1) 
		begin
			parity_bit = parity_bit + 2;
		end
		if (P4 == 1) 
		begin
			parity_bit = parity_bit + 4;
		end
		if (parity_bit != 0) 
		begin
			raw_data_ref[parity_bit-1] = ~raw_data_ref[parity_bit-1];
		end
	endtask

	always begin
		wait((dg_8b.status != idle) || (data_in_11b.status != idle)); //wait until 1 of the input ports has a token
		if((dg_8b.status != idle) && (data_in_11b.status != idle)) //if both ports have tokens
		begin
			if(select == 0)
			begin
				// Select is 0, get 8-bit data from the data generator 
				dg_8b.Receive(dg_data);

				// Calculate and combine parity bits in output
				calc_parity(dg_data, output_data);
				// Set control bit for input processing unit, 2 is predefined to select data from this module
				control = 2;
				#FL;

				fork
					data_out_11b.Send(output_data);
					data_control_out.Send(control);
				join

				#BL;
			end
			else if(select == 1)
			begin
				// Select bit is 1, get 11-bit data from router
				data_in_11b.Receive(router_data);
				raw_data = router_data[10:4];

				hamming_fix(raw_data);


				// Put fixed data into data bucket with 8-bits format: | 4-bit IP | 4-bit Data |
				db_data[3:0] = router_data[3:0];
				db_data[7:4] = {raw_data[6], raw_data[5], raw_data[4], raw_data[2]};

				#FL;
				db_8b.Send(db_data);
				#BL;
			end
			select = ~select;
		end
		else if(dg_8b.status != idle) //if input0 has token ready
		begin
				dg_8b.Receive(dg_data);

				// Calculate and combine parity bits in output
				calc_parity(dg_data, output_data);
				// Set control bit for input processing unit, 2 is predefined to select data from this module
				control = 2;
				#FL;

				fork
					data_out_11b.Send(output_data);
					data_control_out.Send(control);
				join

				#BL;
		end
		else if(data_in_11b.status != idle) //if input1 has token ready
		begin
				data_in_11b.Receive(router_data);
				raw_data = router_data[10:4];
				
				hamming_fix(raw_data);


				// Put fixed data into data bucket with 8-bits format: | 4-bit IP | 4-bit Data |
				db_data[3:0] = router_data[3:0];
				db_data[7:4] = {raw_data[6], raw_data[5], raw_data[4], raw_data[2]};

				#FL;
				db_8b.Send(db_data);
				#BL;
		end

	end
endmodule

module data_generator (interface r);
  parameter WIDTH = 11;
  parameter FL = 0; //ideal environment
  parameter DELAY = 0;
  logic [WIDTH-1:0] SendValue=0;
  always
  begin 
    #DELAY;
    SendValue = $random() % (2**WIDTH);
    #FL;
    r.Send(SendValue);
  end
endmodule

module data_bucket (interface l);
  parameter WIDTH = 11;
  parameter BL = 0; //ideal environment
  logic [WIDTH-1:0] ReceiveValue = 0;
  always
  begin
    l.Receive(ReceiveValue);
    #BL;
    $display("########## Value result is %d", ReceiveValue);
  end
endmodule

module core_tb;
	Channel #(.hsProtocol(P4PhaseBD), .WIDTH(8)) intf[1:0] (); 
	Channel #(.hsProtocol(P4PhaseBD), .WIDTH(11)) intf_11b[1:0] (); 
	Channel #(.hsProtocol(P4PhaseBD), .WIDTH(2)) intf_2b (); 

	data_generator #(.WIDTH(8), .FL(0), .DELAY(5)) dg1(.r(intf[0]));
	data_generator #(.WIDTH(11), .FL(0), .DELAY(5)) dg1(.r(intf_11b[1]));

	core core (.dg_8b(intf[0]), .db_8b(intf[1]), .data_out_11b(intf_11b[0]), .data_control_out(intf_2b), .data_in_11b(intf_11b[1]] ));

	data_bucket #(.WIDTH(2), .BL(0)) db1(.l(intf_2b));
	data_bucket #(.WIDTH(11), .BL(0)) db1(.l(intf_11b[0]));
	data_bucket #(.WIDTH(8), .BL(0)) db1(.l(intf[1]));
endmodule