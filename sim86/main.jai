DEBUG :: true;

insn_table: instruction_table;
should_dump_memory := false;

main :: () {
    print("Using Sim86 DLL Version: %\n", Sim86_GetVersion());

    if __command_line_arguments.count < 2
    {
        print("Please provide one or more 8086 binary files...");
        return;
    }

    Sim86_Get8086InstructionTable(*insn_table);

    file_count := 0;
    while __command_line_arguments.count > 1 {
        __command_line_arguments.count -= 1;
        __command_line_arguments.data += 1;

        arg_string := to_string(__command_line_arguments[0]);

        if (is_cmdl_flag(arg_string))
            continue;

        chip: chip8086;
        chip.ram_size = megabyte(1);
        chip.ram = alloc(xx chip.ram_size); // must be a s64, but it makes no sense to have negative megabytes
        defer { free(chip.ram); chip.ram_size = 0; }
        #if DEBUG
            memset(chip.ram, 0b11110100, xx chip.ram_size);

        if (<<__command_line_arguments.data == null)
            break;

        if !load_program(*chip, arg_string)
            return;

        while(!chip.is_errored && !chip.is_halted)
            cycle_8086(*chip);

        print("\n\nFinal Register Values: \n");
        for chip.registers.array {
            if it_index == 0 continue; // Skip the unused register
            
            reg := register_access.{ Index = xx it_index, Offset = 0, Count = 2 };

            register_name := to_string(Sim86_RegisterNameFromOperand(*reg));
            hex_value := formatInt(chip.registers.array[it_index], base = 16, minimum_digits = 4);

            if it_index == 14 { // If we are printing the flags register...
                flags_string := to_register_flags_string(chip.registers.array[it_index]);
                defer free(flags_string);
                print("\t%: 0x% (%)\n", register_name, hex_value, flags_string);
            } else {
                print("\t%:    0x% (%)\n", register_name, hex_value, chip.registers.array[it_index]);
            }
        }

        if should_dump_memory {
            filename := tprint("sim86_memory_%.data", file_count);
            write_entire_file(filename, cast(*void)chip.ram, cast(int)chip.ram_size);
        }

        file_count += 1; // Inc the file count incase we are dumping the data out
    }

}

is_cmdl_flag :: (argument: string) -> bool {
    if argument == {
        case "-dump";
            should_dump_memory = true;
        case;
            return false;
    };
    return true;
}

megabyte :: (count: u64) -> u64 #expand {
    return count * 1024 * 1024;
}

load_program :: (chip: *chip8086, filename: string, log_errors := true) -> bool {
    log("Loading file '%'...", filename);
    data, success := read_entire_file(filename, log_errors = log_errors);
    if (!success)
        return false;

    defer free(data);
    assert(data.count <= xx chip.ram_size);

    memcpy(chip.ram, data.data, data.count);
    return true;
}

cycle_8086 :: (chip: *chip8086) {
    insn := decode(chip);
    if (!insn.Op)
    {
        log("ERROR: Failed to decode instruction!");
        chip.is_errored = true;
        return;
    }
    chip.registers.ip += xx insn.Size; // IP gets set immediatly after decode on a 8086

    mnemoinc := to_string(Sim86_MnemonicFromOperationType(insn.Op));
    print("> %  ; ", mnemoinc);

    if (!execute(chip, insn))
    {
        log("ERROR: Failed to execute instruction (%)", mnemoinc);
        chip.is_errored = true;
        return;
    }

    chip.cycles += 1;
    print("\n");
}

decode :: (chip: *chip8086) -> instruction {
    insn: instruction;
    Sim86_Decode8086Instruction(xx (chip.ram_size - xx chip.registers.ip), chip.ram + chip.registers.ip, *insn);
    return insn;
}

execute :: (chip: *chip8086, insn: instruction) -> bool {
    if insn.Op == {
        case .hlt;
            chip.is_halted = true;
            print("Halted after % cycles", chip.cycles);

        case .mov;
            value := get_value_from_operand(chip, insn.Operands[1]);
            write_value_to_location(chip, insn.Operands[0], value, insn.Flags);

        case .add;
            left   := get_value_from_operand(chip, insn.Operands[0]);
            right  := get_value_from_operand(chip, insn.Operands[1]);
            result := left + right;

            write_value_to_location(chip, insn.Operands[0], result, insn.Flags);
            emulate_flags(chip, result);

        case .sub;
            left   := get_value_from_operand(chip, insn.Operands[0]);
            right  := get_value_from_operand(chip, insn.Operands[1]);
            result := left - right;

            write_value_to_location(chip, insn.Operands[0], result, insn.Flags);
            emulate_flags(chip, result);

        case .cmp;
            left   := get_value_from_operand(chip, insn.Operands[0]);
            right  := get_value_from_operand(chip, insn.Operands[1]);
            result := left - right;

            emulate_flags(chip, result);

        case .jne;
            operand := get_value_from_operand(chip, insn.Operands[0]);
            dont_jump_on_flags(chip, xx register_flags.ZERO, xx operand);

        case;
            return false;
    };

    return true;
}

get_value_from_operand :: (chip: *chip8086, operand: instruction_operand) -> s32 {
    if #complete operand.Type == {
        case .None;
            return -1234;

        case .Register;
            mask: s32 = xx ~(~0 << (operand.Register.Count * 8)) << (operand.Register.Offset * 8);
            return (chip.registers.array[operand.Register.Index] & mask) >> (operand.Register.Offset * 8);

        case .Memory;
            // Assumes 16 bit operation "Wide" flag set
            // Assumes no explicit segments
            assert((operand.Address.Flags & xx effective_address_flag.Address_ExplicitSegment) == 0);

            effective_address := operand.Address.Displacement;
            for operand.Address.Terms {
                register_operand := instruction_operand.{ Type = .Register, Register = it.Register };
                effective_address += get_value_from_operand(chip, register_operand) * it.Scale;
            }
            print("[value] effective address = % ", effective_address);

            low_byte  := chip.ram[effective_address];
            high_byte := chip.ram[effective_address + 1];

            return high_byte << 8 | low_byte;



        case .Immediate;
            return operand.Immediate.Value;
    };
}

get_location_from_operand :: (chip: *chip8086, operand: instruction_operand) -> *u8 {
    if #complete operand.Type == {
        case .None;
            return null;

        case .Register;
            return (cast(*u8) *chip.registers.array[operand.Register.Index]) + operand.Register.Offset;

        case .Memory;
            // Assumes 16 bit operation "Wide" flag set
            // Assumes no explicit segments
            assert((operand.Address.Flags & xx effective_address_flag.Address_ExplicitSegment) == 0);

            effective_address := operand.Address.Displacement;
            for operand.Address.Terms {
                register_operand := instruction_operand.{ Type = .Register, Register = it.Register };
                effective_address += get_value_from_operand(chip, register_operand) * it.Scale;
            }
            print("[location] effective address = % ", effective_address);
            return *chip.ram[effective_address];

        case .Immediate;
            return null;
    };
}

jump_on_flags :: (chip: *chip8086, flags: u16, ip_displacement: s16) {
    if (chip.registers.flags & flags)
        chip.registers.ip += ip_displacement;
}

dont_jump_on_flags :: (chip: *chip8086, flags: u16, ip_displacement: s16) {
    if !(chip.registers.flags & flags)
        chip.registers.ip += ip_displacement;
}

write_value_to_location :: (chip: *chip8086, location_operand: instruction_operand, value: s32, flags: instruction_flag) {
    location := get_location_from_operand(chip, location_operand);

    if flags & .Wide then
        <<(cast(*s16)location) = cast(s16) value;
    else
        << location = cast(u8)value;
}

emulate_flags :: (chip: *chip8086, new_value: s32) {
    // TODO(Steven): this will not work for 8 bit instructions...
    new_flags: u16 = 0;

    // Test Auxiliary Carry Flag
    // TODO(Steven): Not-Implemented

    // Test Carry Flag
    // TODO(Steven): Not-Implemented

    // Test Overflow Flag
    new_flags |= xx ifx new_value & 0xFFFF0000 then register_flags.OVERFLOW else 0;

    // Test Sign Flag
    new_flags |= xx ifx new_value & 0x8000 then register_flags.SIGN else 0;

    // Test Parity Flag
    count: s8 = 7;
    acc:   u8 = 0;
    while count >= 0 {
        count -= 1;
        acc += xx !!(new_value & (1 << count));
    }
    new_flags |= xx ifx acc % 2 == 0 then register_flags.PARITY else 0;

    // Test Zero Flag
    new_flags |= xx ifx new_value == 0 then register_flags.ZERO else 0;

    // Set the new flags
    chip.registers.flags = new_flags;
}

to_register_flags_string :: (flags: u16) -> string {
    output: [..] u8;
    register_flags_type_info := type_info(register_flags);

    for register_flags_type_info.values {
        array_add(*output, ifx flags & it then register_flags_type_info.names[it_index][0] else #char " ");
    }

    return xx output;
}

chip8086 :: struct {
    cycles: u64;

    ram: *u8;
    ram_size: u64;

    is_errored: bool;
    is_halted: bool;

    registers: union {
        struct {
            unused: u16;
            ax: u16;
            bx: u16;
            cx: u16;
            dx: u16;
            sp: u16;
            bp: u16;
            si: u16;
            di: u16;
            es: u16;
            cs: u16;
            ss: u16;
            ds: u16;
            ip: s16;
            flags: u16;
        };
        array: [15] u16;
    };
}

register_flags :: enum u16 {
    CARRY     :: (1 <<  0); //    1's bit
    PARITY    :: (1 <<  2); //    4's bit
    AUX_CARRY :: (1 <<  4); //   16's bit
    ZERO      :: (1 <<  6); //   64's bit
    SIGN      :: (1 <<  7); //  128's bit
    TRAP      :: (1 <<  8); //  256's bit
    INTERRUPT :: (1 <<  9); //  512's bit
    DIRECTION :: (1 << 10); // 1024's bit
    OVERFLOW  :: (1 << 11); // 2048's bit
}

#import "Basic";
#import "File";
#import "sim86";
