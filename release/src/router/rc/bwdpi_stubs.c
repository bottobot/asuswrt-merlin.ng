/*
 * bwdpi_stubs.c
 *
 * Link-time stubs for BWDPI=n builds (RTCONFIG_BWDPI unset, RTCONFIG_AMAS set).
 *
 * The prebuilt amas_lib.o still references a few Trend Micro DPI engine
 * entry points that normally come from libbwdpi.so (rc links -lbwdpi only
 * under RTCONFIG_BWDPI).  Every call site in amas_lib.o is guarded by
 * check_tdts_module_exist() != 0, so with the engine absent these are never
 * reached; they only have to exist.  They report "engine not present / empty
 * list / nothing done".
 *
 * check_bwdpi_nvram_setting() and check_wrs_switch() are provided by
 * shared/bwdpi_utils.c (libshared.so) in the same configuration.
 *
 * Compiled only when RTCONFIG_BWDPI is not "y" (see rc/Makefile).
 */
#include <stddef.h>
#include <stdint.h>

/* 0: tdts kernel module / DPI engine not loaded */
int check_tdts_module_exist(void)
{
	return 0;
}

/* empty list: *output = NULL, *buf_used_len = 0 (callers check for NULL) */
int get_fw_mesh_extender(void **output, unsigned int *buf_used_len)
{
	if (output)
		*output = NULL;
	if (buf_used_len)
		*buf_used_len = 0;
	return 0;
}

/* real prototype: int get_fw_user_list(udb_ioctl_entry_t **output, uint32_t *used_len) */
int get_fw_user_list(void **output, uint32_t *used_len)
{
	if (output)
		*output = NULL;
	if (used_len)
		*used_len = 0;
	return 0;
}

/* no-op */
int mesh_set_extender(char *macstr, uint8_t action)
{
	(void)macstr;
	(void)action;
	return 0;
}
