// Build public examples against this checkout under an isolated V module path.
import os
import rand

const examples = ['object_pool', 'buffer_pool', 'range_allocator', 'linear_allocator',
	'ring_allocator', 'buddy_allocator', 'synchronized_allocators', 'workspaces', 'deferred_ring',
	'deferred_jobs']
const benchmark_operations = '1000000'
const quick_benchmark_operations = '50000'

fn run_command(compiler string, args []string) ! {
	mut child := os.new_process(compiler)
	child.set_args(args)
	child.run()
	child.wait()
	status := child.code
	child.close()
	if status != 0 {
		return error_with_code('V failed while running ${args.join(' ')}', status)
	}
}

fn run_samples(args []string) ! {
	if args.len == 0 || args[0] !in ['examples', 'benchmarks'] {
		return error_with_code('Usage: v run scripts/run_samples.vsh examples | benchmarks [--quick | operations]',
			2)
	}
	root := os.real_path(os.dir(@DIR))
	configured := os.getenv('VMODULES')
	mut temporary_modules := ''
	defer {
		if temporary_modules != '' {
			os.rmdir_all(temporary_modules) or {
				eprintln('Could not remove ${temporary_modules}: ${err}')
			}
		}
	}
	// CI already checks out this module under its namespaced module directory.
	if configured == '' || os.real_path(os.join_path(configured, 'antono2', 'memory')) != root {
		isolated := os.join_path(os.temp_dir(), 'v-memory-modules-' + rand.uuid_v4())
		os.mkdir(isolated)!
		temporary_modules = isolated
		namespace := os.join_path(isolated, 'antono2')
		os.mkdir(namespace)!
		os.symlink(root, os.join_path(namespace, 'memory'))!
		os.setenv('VMODULES', isolated, true)
	}
	compiler := os.getenv_opt('VEXE') or { @VEXE }

	if args[0] == 'examples' {
		for example in examples {
			run_command(compiler, ['run', os.join_path(root, 'examples', example)])!
		}
		return
	}

	count := args[1] or { '' }
	operations := match count {
		'--quick' { quick_benchmark_operations }
		'' { benchmark_operations }
		else { count }
	}

	run_command(compiler, ['version'])!
	run_command(compiler, ['-prod', 'run', os.join_path(root, 'benchmarks'), operations])!
}

run_samples(os.args[1..]) or {
	eprintln(err.msg())
	exit(if err.code() > 0 { err.code() } else { 1 })
}
