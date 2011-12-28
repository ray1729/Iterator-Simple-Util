package Iterator::Simple::Util;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( igroup ireduce isum
                     imax imin imaxstr iminstr imax_by imin_by imaxstr_by iminstr_by
                     iany inone inotall
                     ifirstval ilastval
                     ibefore ibefore_incl iafter iafter_incl
                     inatatime
               )
             ]
};

use Const::Fast;
use Iterator::Simple qw( iter iterator ichain );

const my $TRUE  => !0;
const my $FALSE => !1;

=pod

    my ( $next_record ) = next_record();

    while ( $next_record ) {

        my $base_record = $next_record;
        my @group = ();

        while ( $next_record and is_same_group( $base_record, $next_record ) ) {
            push @group $next_record;
            $next_record = next_record();
        }

        process_group( \@group );
    }

    my $iter = igroup( { $a->[0] eq $b->[0] } [ [ a => 1 ], [ a => 2 ], [ b => 1, b => 2 ], [ c => 1, c => 2 ] ] );

    while ( my $grit = $iter->next ) {
        while( my $record = $grit->next ) {
          # Do something with $record
        }
    }

=cut

sub igroup (&$) {
    my ( $is_same_group, $base_iter ) = @_;    

    _ensure_coderef( $is_same_group );

    $base_iter = iter $base_iter;

    my $next_record = $base_iter->next;

    # Localize caller's $a and $b
    my ( $caller_a, $caller_b ) = do {
        require B;
        my $caller = B::svref_2object( $is_same_group )->STASH->NAME;        
        no strict 'refs';
        map  \*{$caller.'::'.$_}, qw( a b );
    };
    local ( *$caller_a, *$caller_b );
    
    return iterator {
        defined( my $base_record = $next_record )
            or return;

        return iterator {
            return unless defined $next_record;
            ( *$caller_a, *$caller_b ) = \( $base_record, $next_record );
            return unless $is_same_group->();
            my $res = $next_record;
            $next_record = $base_iter->next;
            return $res;
        };
    };
}

sub ireduce (&$;$) {    

    my ( $code, $init_val, $iter );
    
    if ( @_ == 2 ) {
        ( $code, $iter ) = @_;
    }
    else {
        ( $code, $init_val, $iter ) = @_;
    }

    _ensure_coderef( $code );
    $iter = iter $iter;
    
    # Localize caller's $a and $b
    my ( $caller_a, $caller_b ) = do {
        require B;
        my $caller = B::svref_2object( $code )->STASH->NAME;        
        no strict 'refs';
        map  \*{$caller.'::'.$_}, qw( a b );
    };
    local ( *$caller_a, *$caller_b ) = \my ( $x, $y );    

    $x = @_ == 3 ? $init_val : $iter->next;
    
    defined( $x )
        or return;

    defined( $y = $iter->next )
        or return $x;
    
    while( defined $x and defined $y ) {
        $x = $code->();
        $y = $iter->next;
    }
    
    return $x;
}

sub isum ($;$) {
    my ( $init_val, $iter );

    if ( @_ == 1 ) {
        $init_val = 0;
        $iter = $_[0];
    }
    else {
        ( $init_val, $iter ) = @_;
    }

    $iter = iter $iter;

    ireduce { $a + $b } $init_val, $iter;
}

sub imax ($) {
    ireduce { $a > $b ? $a : $b } iter( shift );
}

sub imin ($) {
    ireduce { $a < $b ? $a : $b } iter( shift );
}

sub imax_by (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $code = _wrap_code( $code );
        
    ireduce { $code->($a) > $code->($b) ? $a : $b } iter $iter;    
}

sub imin_by (&$) {
    my ( $code, $iter ) = @_;
    
    _ensure_coderef( $code );
    $code = _wrap_code( $code );
    
    ireduce { $code->($a) < $code->($b) ? $a : $b } iter $iter;
}

sub imaxstr ($) {
    ireduce { $a gt $b ? $a : $b } iter( shift );
}

sub iminstr ($) {
    ireduce { $a lt $b ? $a : $b } iter( shift );
}

sub imaxstr_by (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $code = _wrap_code( $code );
    
    ireduce { $code->($a) gt $code->($b) ? $a : $b } iter $iter;
}

sub iminstr_by (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $code = _wrap_code( $code );
    
    ireduce { $code->($a) lt $code->($b) ? $a : $b } iter $iter;
}

sub iany (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $iter = iter $iter;
    
    while( defined( $_ = $iter->next ) ) {
        $code->() and return $TRUE;
    }

    return $FALSE;
}

sub inone (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $iter = iter $iter;

    while( defined( $_ = $iter->next ) ) {
        $code->() and return $FALSE;
    }

    return $TRUE;
}

sub inotall (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $iter = iter $iter;

    while( defined( $_ = $iter->next ) ) {
        return $TRUE if ! $code->();
    }

    return $FALSE;
}

sub ifirstval (&$) {
    my ( $code, $iter ) = @_;
    _ensure_coderef( $code );
    $iter = iter $iter;
    
    while( defined( $_ = $iter->next ) ) {
        $code->() and return $_;
    }

    return;
}

sub ilastval (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $iter = iter $iter;
    
    my $val;
    while( defined( $_ = $iter->next ) ) {
        $val = $_ if $code->();
    }

    return $val;
}

sub ibefore (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $iter = iter $iter;

    return iterator {
        defined( $_ = $iter->next )
            or return;
        $code->()
            and return;
        return $_;
    };
}

sub ibefore_incl (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $iter = iter $iter;

    my $done = $FALSE;
    
    return iterator {
        not( $done ) and defined( $_ = $iter->next )
            or return;
        $code->() and $done = $TRUE;
        return $_;
    };
}

sub iafter (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $iter = iter $iter;

    while( defined( $_ = $iter->next ) ) {
        last if $code->();
    }

    return $iter;
}

sub iafter_incl (&$) {
    my ( $code, $iter ) = @_;

    _ensure_coderef( $code );
    $iter = iter $iter;

    while( defined( $_ = $iter->next ) ) {
        last if $code->();
    }

    return ichain iter( [$_] ), $iter;
}

sub inatatime ($;$) {
    my ($kicks, $iter) = @_;

    $iter = iter $iter;

    return iterator {
        my @vals;

        for (1 .. $kicks) {
            my $val = $iter->next;
            last unless defined $val;
            push @vals, $val;
        }
        return @vals ? \@vals : undef;
    };
}

sub _ensure_coderef {
    unless( ref( shift ) eq 'CODE' ) {
        require Carp;
        Carp::croak("Not a subroutine reference");
    }
}

sub _wrap_code {
    my $code = shift;

    return sub {
        $_ = shift;
        $code->();
    };
}

1;

__END__
