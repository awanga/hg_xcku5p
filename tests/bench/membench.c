// SPDX-License-Identifier: MIT
// Working-set sweep for the CPU cache study: sequential read, dependent random loads (pointer chase) and copy,
// measured with the simulation time counter (1 tick = 1 core clock in the VexiiRiscv testbench).
// Output lines: "MB <bytes> seq <cyc/64B x100> chase <cyc/access x100> copy <cyc/64B x100>"
#include "sim.h"

#define BASE_PTR ((volatile unsigned long *)0x80100000UL)
#define LINE 64UL
#define MAXB (2UL * 1024 * 1024)

static void put_u(unsigned long v)
{
	char b[24];
	int n = 0;

	if (!v)
		b[n++] = '0';
	while (v) {
		b[n++] = '0' + v % 10;
		v /= 10;
	}
	while (n)
		sim_putchar(b[--n]);
}

static unsigned long xs = 0x2545F491UL;

static unsigned long rnd(void)
{
	xs ^= xs << 13;
	xs ^= xs >> 17;
	xs ^= xs << 5;
	return xs;
}

int main(void)
{
	static const unsigned long sizes[] = { 4096, 8192, 16384, 32768, 65536, 131072, 262144 };
	unsigned long i, k, s;

	for (k = 0; k < sizeof(sizes) / sizeof(sizes[0]); k++) {
		unsigned long bytes = sizes[k];
		unsigned long lines = bytes / LINE;
		unsigned long words = bytes / sizeof(unsigned long);
		volatile unsigned long *a = BASE_PTR;
		volatile unsigned long *b = BASE_PTR + MAXB / sizeof(unsigned long);
		unsigned long reps = (bytes >= 65536) ? 1 : 2;
		unsigned long t0, t_seq, t_chase, t_copy, sum = 0, p = 0, n_acc;
		unsigned long r;

		/* random cyclic permutation over the cache lines (Sattolo), stored in word 0 of each line */
		for (i = 0; i < lines; i++)
			a[i * (LINE / sizeof(unsigned long))] = i;
		for (i = lines - 1; i > 0; i--) {
			unsigned long j = rnd() % i;
			unsigned long t = a[i * 8];

			a[i * 8] = a[j * 8];
			a[j * 8] = t;
		}
		/* warm: one pass (cache-resident sizes then measure steady state; larger sizes always miss) */
		for (i = 0; i < words; i++)
			sum += a[i];

		t0 = sim_time();
		for (r = 0; r < reps; r++)
			for (i = 0; i < words; i += 8)
				sum += a[i] + a[i + 1] + a[i + 2] + a[i + 3] + a[i + 4] + a[i + 5] + a[i + 6] + a[i + 7];
		t_seq = sim_time() - t0;

		n_acc = lines * reps;
		t0 = sim_time();
		for (s = 0; s < n_acc; s++)
			p = a[p * 8];
		t_chase = sim_time() - t0;

		t0 = sim_time();
		for (r = 0; r < reps; r++)
			for (i = 0; i < words; i++)
				b[i] = a[i];
		t_copy = sim_time() - t0;

		sim_puts("MB ");
		put_u(bytes);
		sim_puts(" seq ");
		put_u(t_seq * 100 / (lines * reps));
		sim_puts(" chase ");
		put_u(t_chase * 100 / n_acc);
		sim_puts(" copy ");
		put_u(t_copy * 100 / (lines * reps));
		sim_puts(" chk ");
		put_u((sum + p) & 1);
		sim_putchar('\n');
	}
	return 0;
}
