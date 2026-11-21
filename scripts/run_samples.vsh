// Build public examples against this checkout under an isolated V module path.
import os
import rand
import time

const examples = ['object_pool', 'buffer_pool', 'range_allocator', 'linear_allocator',
	'ring_allocator', 'buddy_allocator', 'synchronized_allocators', 'workspaces', 'deferred_ring',
	'deferred_jobs']
const benchmark_operations = '1000000'
const quick_benchmark_operations = '50000'
// Keep tagged baselines comparable with the existing release benchmark history.
const baseline_benchmark_operations = '250000'
const report_poll_interval = 10 * time.millisecond
const invalid_arguments_status = 2
const usage = 'Usage: v run scripts/run_samples.vsh examples | benchmarks [--quick | --baseline | operations] [--report FILE]'

fn benchmark_arguments(args []string) !(string, string) {
	mut count := ''
	mut report := ''
	for i := 0; i < args.len; i++ {
		match args[i] {
			'--report' {
				if report != '' || i + 1 >= args.len || args[i + 1] == '' {
					return error_with_code(usage, invalid_arguments_status)
				}
				i++
				report = args[i]
			}
			else {
				if count != '' {
					return error_with_code(usage, invalid_arguments_status)
				}
				count = args[i]
			}
		}
	}
	return count, report
}

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

fn run_reported(compiler string, args []string, mut report os.File) ! {
	mut child := os.new_process(compiler)
	child.set_args(args)
	child.set_redirect_stdio()
	child.run()
	defer {
		if child.is_alive() {
			child.signal_term()
			child.wait()
		}
		child.close()
	}
	for {
		live := child.is_alive()
		out := child.stdout_read()
		err := child.stderr_read()
		if out != '' {
			report.write_string(out)!
			report.flush()
			print(out)
		}
		if err != '' {
			eprint(err)
		}
		if out == '' && err == '' {
			if !live {
				break
			}
			time.sleep(report_poll_interval)
		}
	}
	child.wait()
	if child.code != 0 {
		return error_with_code('V failed while running ${args.join(' ')}', child.code)
	}
}

fn run_benchmarks(compiler string, root string, count string, report_path string) ! {
	operations := match count {
		'--quick' { quick_benchmark_operations }
		'--baseline' { baseline_benchmark_operations }
		'' { benchmark_operations }
		else { count }
	}

	commands := [['version'], ['-prod', 'run', os.join_path(root, 'benchmarks'), operations]]
	if report_path == '' {
		for command in commands {
			run_command(compiler, command)!
		}
		return
	}

	mut report := os.create(report_path)!
	defer { report.close() }
	if count == '--baseline' {
		header := 'ref=${os.getenv('GITHUB_REF_NAME')} commit=${os.getenv('GITHUB_SHA')} platform=${os.getenv('RUNNER_OS')}/${os.getenv('RUNNER_ARCH')} build=-prod\n'
		report.write_string(header)!
		report.flush()
		print(header)
	}
	for command in commands {
		run_reported(compiler, command, mut report)!
	}
}

fn run_samples(args []string) ! {
	if args.len == 0 || args[0] !in ['examples', 'benchmarks'] {
		return error_with_code(usage, invalid_arguments_status)
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

	count, report_path := benchmark_arguments(args[1..])!
	run_benchmarks(compiler, root, count, report_path)!
}

run_samples(os.args[1..]) or {
	eprintln(err.msg())
	exit(if err.code() > 0 { err.code() } else { 1 })
}
