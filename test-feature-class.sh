#!/bin/sh

# A script not intended for real merge, just to make it easier for me to
# remember how to fast-test this bit

TEST_JOBS=3 PERL_DESTRUCT_LEVEL=2 exec \
  ./perl t/harness t/class/*.t t/lib/croak.t lib/warnings.t t/porting/diag.t t/porting/podcheck.t
