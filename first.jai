// first.jai
// This file contains the build instructions for the Jai compiler to
// build the project executable and any other tools
//

#run {
    options := get_build_options();

    // Tell the compiler not to produce an executable for this file
    set_build_options_dc(.{ do_output = false });

    // Retarget working directory to the projects root
    set_working_directory(#filepath);

    // Include modules in the vendor folder
    import_path: [..] string;
    array_add(*import_path, "modules");
    array_add(*import_path, ..options.import_path);
    options.import_path = import_path;

    // Setup optimizations
    set_optimization(*options, .DEBUG); // TODO(Steven): allow command line args to specifiy optimization levels
    
    // Name the target executable
    options.output_executable_name = "sim86";
    build_sim86(options);

    options.output_executable_name = "memory_viewer";
    build_memory_viewer(options);
}

build_sim86 :: (options: Build_Options) {
    build_project(options, "sim86/main.jai");
}

build_memory_viewer :: (options: Build_Options) {
    build_project(options, "memory_viewer/main.jai");
}

build_project :: (options: Build_Options, main_filepath: string) {
    // Create the workspace which will build the actual executable
    workspace := compiler_create_workspace(options.output_executable_name);
    set_build_options(options, workspace);

    compiler_begin_intercept(workspace);
    add_build_file(main_filepath, workspace);

    // Intercept compiler messages here
    //

    compiler_end_intercept(workspace);
}


#import "Basic";
#import "Compiler";
