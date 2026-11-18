// Run allocator validation against a temporary module link to this checkout.
import os
import rand

const sanitizer_frame_flag = '-fno-omit-frame-pointer'
const repeated_examples = ['workspaces', 'deferred_ring', 'deferred_jobs']
const example_repetitions = 2
const quick_benchmark_operations = '50000'

fn execute(executable string, args []string) ! {
	mut child := os.new_process(executable)
	child.set_args(args)
	child.run()
	child.wait()
	status := child.code
	child.close()
	if status != 0 {
		return error_with_code('${executable} failed: ${args.join(' ')}', status)
	}
}

fn set_default(name string, value string) {
	if os.getenv(name) == '' {
		os.setenv(name, value, true)
	}
}

fn sanitize(compiler string, root string, thread_only bool) ! {
	mut sanitizer := os.getenv('V_SANITIZER_CC')
	if sanitizer == '' {
		sanitizer = 'clang'
	}
	resolved := os.find_abs_path_of_executable(sanitizer) or { '' }
	if resolved == '' || !os.is_file(resolved) || !os.is_executable(resolved) {
		return error('sanitizer compiler not found: ${sanitizer}')
	}
	mut options := []string{}
	mut target := root
	mut flag := '-fsanitize=address,undefined'
	if thread_only {
		// Boehm's signal handler conflicts with the V 0.5.2 ThreadSanitizer lane.
		options << ['-gc', 'none']
		target = os.join_path(root, 'synchronized_allocators_concurrency_test.v')
		flag = '-fsanitize=thread'
		set_default('TSAN_OPTIONS', 'halt_on_error=1:second_deadlock_stack=1')
	} else {
		// Compiler/runtime lifetime allocations are outside this access-safety gate.
		set_default('ASAN_OPTIONS', 'detect_leaks=0:halt_on_error=1')
		set_default('UBSAN_OPTIONS', 'halt_on_error=1:print_stacktrace=1')
	}
	options << ['-cc', sanitizer, '-cflags', flag, '-cflags', sanitizer_frame_flag, '-ldflags',
		flag, 'test', target]
	execute(compiler, options)!
}

fn test_v3(compiler string, root string, temporary string) ! {
	scripts := os.join_path(root, 'scripts')
	execute(compiler, ['run', os.join_path(scripts, 'compatibility.vsh'), '--profile', 'v3'])!
	execute(compiler, ['run', os.join_path(scripts, 'doctor.vsh'), '--v', compiler, '--profile',
		'v3', '--modules', temporary])!
	execute(compiler, ['test', root])!
	execute(compiler, ['-new-compiler', 'test', root])!
	for example in repeated_examples {
		executable := os.join_path(temporary, example)
		source := os.join_path(root, 'examples', example)
		for _ in 0 .. example_repetitions {
			execute(compiler, ['-new-compiler', '-o', executable, source])!
			execute(executable, [])!
		}
	}
	execute(compiler, ['-new-compiler', '-prod', 'run', os.join_path(root, 'benchmarks'),
		quick_benchmark_operations])!
}

fn run_validation(args []string) ! {
	mode := args[0] or { '' }
	if mode !in ['tests', 'sanitizers', 'thread-sanitizer', 'v3'] {
		return error_with_code('Usage: v run scripts/run_validation.vsh tests [FILE_OR_DIR] | sanitizers | thread-sanitizer | v3',
			2)
	}
	root := os.real_path(os.dir(@DIR))
	temporary := os.join_path(os.temp_dir(), 'v-memory-validation-' + rand.uuid_v4())
	os.mkdir(temporary)!
	defer {
		os.rmdir_all(temporary) or { eprintln('Could not remove ${temporary}: ${err}') }
	}
	namespace := os.join_path(temporary, 'antono2')
	os.mkdir(namespace)!
	os.symlink(root, os.join_path(namespace, 'memory'))!
	os.setenv('VMODULES', temporary, true)
	vexe := os.getenv('VEXE')
	compiler := if vexe == '' { @VEXE } else { vexe }
	match mode {
		'tests' {
			target := args[1] or { '' }
			execute(compiler, ['test', if target == '' { root } else { target }])!
		}
		'sanitizers' {
			sanitize(compiler, root, false)!
		}
		'thread-sanitizer' {
			sanitize(compiler, root, true)!
		}
		else {
			test_v3(compiler, root, temporary)!
		}
	}
}

run_validation(os.args[1..]) or {
	eprintln(err.msg())
	exit(if err.code() > 0 { err.code() } else { 1 })
}
