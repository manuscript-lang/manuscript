/* dropq.h: what the fault module needs of the drop worklist. Internal to src/runtime/core. */
#ifndef MS_CORE_DROPQ_H
#define MS_CORE_DROPQ_H

/* Forgets the nesting of drops that a guard jump skipped the leaves of. */
void msdrop_reset(void);

#endif
