/*
 * memory_viewer.jai
 *
 * This is a simple visualizer for the memory dump that the 8086 simulator produces.
 * It will interpret whatever file you give it as RGBA8 values and render that to a 
 * texture and let you pan and zoom around.
 *
 * Using Jai's built in modules, making a visualizer like this was very easy! I mean,
 * this file is only ~140 lines long!
 */

should_quit := false;
window_width, window_height := 1920/2, 1080/2;
view_scale := 1.0;
view_offset: Vector2;

main :: () {
    program_name  := next_cmdl_arg();

    if __command_line_arguments.count < 4 {
        log_error("USAGE: % <width> <height> <offset> <data file>", program_name);
        return;
    }

    width  := to_integer(next_cmdl_arg());
    height := to_integer(next_cmdl_arg());
    offset := to_integer(next_cmdl_arg());
    data_filename := next_cmdl_arg();

    window_width = width * 4;
    window_height = height * 4;

    log("Viewer Parameters:\n\twidth:  %\n\theight: %\n\toffset: %\n\tdata filename: %", width, height, offset, data_filename);

    assert(width <= 1920/2);
    assert(height <= 1080/2);

    window := create_window(window_name = "Memory Viewer", width = window_width, height = window_height);
    Simp.set_render_target(window);

    texture, success := init_texture(data_filename, xx width, xx height, xx offset);
    if !success {
        log_error("ERROR: Unable to init texture, exiting...");
        return;
    }

    while !should_quit {
        reset_temporary_storage();
        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);
            if it.window == window {
                window_width = it.width;
                window_height = it.height;
            }
        }

        Simp.clear_render_target(.2, .3, .3, 1);

        // Tick
        for event : Input.events_this_frame {
            if event.type == .QUIT || (event.type == .KEYBOARD && event.key_code == .ESCAPE) {
                should_quit = true;
                break;
            }

            if event.type == {
                case .MOUSE_WHEEL;
                    view_scale += (event.wheel_delta / event.typical_wheel_delta);
            }
        }

        if Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] == .DOWN || Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] == .DOWN {
            view_offset += make_vector2(xx Input.mouse_delta_x, xx -Input.mouse_delta_y);
        }

        // Render
        center := make_vector2(cast(float)(window_width/2)-(width * view_scale/2), cast(float)window_height/2-(width * view_scale/2));
        render_sprite_quad(*texture, center + view_offset, .{ xx width * view_scale, xx height * view_scale }, .{1,1,1,1});
        Simp.swap_buffers(window);
    }
}

init_texture :: (data_filename: string, width: s32, height: s32, offset: s32) -> Simp.Texture, bool {
    bitmap: Simp.Bitmap;
    result: Simp.Texture;

    Simp.bitmap_alloc(*bitmap, width, height, .RGBA8);
    defer Simp.deinit(*bitmap);

    data, success := read_entire_file(data_filename, log_errors = true);
    if !success
        return result, false;

    assert(bitmap.stride * bitmap.height <= data.count - offset);
    memcpy(bitmap.data.data, data.data + offset, bitmap.stride * bitmap.height);
    
    success = Simp.texture_load_from_bitmap(*result, *bitmap);
    if !success {
        log_error("ERROR: Unable to load texture from bitmap");
        return result, false;
    }

    return result, true;
}

// Modified from "render_sprite_quad_centered" in invaders.jai
render_sprite_quad :: (texture: *Simp.Texture, _pos: Vector2, size: Vector2, color: Vector4) {
    Simp.set_shader_for_images(texture);

    p0 := _pos.x;
    p1 := _pos.y;
    p2 := _pos.x + size.x;
    p3 := _pos.y + size.y;

    Simp.immediate_quad(p0, p1, p2, p3, color);
}

next_cmdl_arg :: () -> string {
    if __command_line_arguments.count == 0 {
        return "";
    }

    output := to_string(__command_line_arguments[0]);

    __command_line_arguments.count -= 1;
    __command_line_arguments.data += 1;

    return output;
}

#import "Basic";
#import "Window_Creation";
#import "File";
#import "Math";
Input :: #import "Input";
Simp  :: #import "Simp";
