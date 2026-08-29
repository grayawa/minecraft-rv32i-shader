import static org.lwjgl.util.shaderc.Shaderc.*;
import static org.lwjgl.system.MemoryUtil.*;

import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;

public final class ShadercCheck {
    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            throw new IllegalArgumentException("Pass one or more shader files");
        }

        long compiler = shaderc_compiler_initialize();
        long options = shaderc_compile_options_initialize();
        if (compiler == 0L || options == 0L) {
            throw new IllegalStateException("ShaderC initialization failed");
        }

        try {
            shaderc_compile_options_set_source_language(options, shaderc_source_language_glsl);
            shaderc_compile_options_set_target_env(options, shaderc_target_env_vulkan,
                    shaderc_env_version_vulkan_1_0);
            shaderc_compile_options_set_auto_bind_uniforms(options, true);
            shaderc_compile_options_set_auto_map_locations(options, true);

            boolean failed = false;
            for (String fileName : args) {
                Path path = Path.of(fileName);
                String source = Files.readString(path);
                int kind = fileName.endsWith(".vsh")
                        ? shaderc_glsl_vertex_shader
                        : shaderc_glsl_fragment_shader;
                ByteBuffer sourceBuffer = memUTF8(source, false);
                ByteBuffer fileNameBuffer = memUTF8(path.getFileName().toString(), true);
                ByteBuffer entryPointBuffer = memUTF8("main", true);
                try {
                    long result = shaderc_compile_into_spv(
                            compiler, sourceBuffer, kind, fileNameBuffer,
                            entryPointBuffer, options);
                    try {
                        int status = shaderc_result_get_compilation_status(result);
                        String message = shaderc_result_get_error_message(result);
                        if (status == shaderc_compilation_status_success) {
                            System.out.println("SHADER OK " + path);
                        } else {
                            failed = true;
                            System.err.println("SHADER BAD " + path
                                    + System.lineSeparator() + message);
                        }
                    } finally {
                        shaderc_result_release(result);
                    }
                } finally {
                    memFree(sourceBuffer);
                    memFree(fileNameBuffer);
                    memFree(entryPointBuffer);
                }
            }
            if (failed) {
                System.exit(1);
            }
        } finally {
            shaderc_compile_options_release(options);
            shaderc_compiler_release(compiler);
        }
    }
}
