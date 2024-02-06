#include <stdint.h>
#include <stdio.h>
#define SZ   (32768)
#define L(X) ((X)%SZ)
int main(int s, char **v) {
	static uint16_t m[SZ];
	unsigned pc = 0;
	for (int i = 1, d = 0; i < s; i++) {
		FILE *f = fopen(v[i], "r");
		if (!f)
			return 1;
		while (fscanf(f, "%d", &d) > 0)
			m[L(pc++)] = d;
		if (fclose(f) < 0)
			return 2;
	}
	for (unsigned i = 0; i < pc; i++) {
		if (fprintf(stdout, "%04X\n", m[L(i)]) < 0)
			return 3;
	}
	return 0;
}
