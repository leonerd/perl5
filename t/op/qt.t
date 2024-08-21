#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use feature 'qt';
no warnings 'experimental::qt';

# Literal quoting
is( qt{some literal text}, "some literal text", 'qt{} as literal' );

# qt syntax is feature-guarded
{
    no feature 'qt';

    sub qt { return "regular function <@_>" }

    is( qt(123), 'regular function <123>',
        'qt parses as normal function with feature disabled' );
}

done_testing();
