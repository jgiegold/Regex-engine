# A set of conditions that use MSER-inspired methods.
use strict;
use warnings;

# Invoke PDL::PP
my $base_name;
BEGIN {
	# .PL scripts are sent their filename, sans the .PL part. That's almost what
	# PDL::PP expects to see, so massage it into the proper form:
	$base_name = $ARGV[0];
	$base_name =~ s/\.pm//;
	
	# Handle backslashes for Windows paths:
	$base_name =~ s/\\/\\\\/g;
}
use PDL::PP (qw(Regex::Engine::MSER Regex::Engine::MSER), $base_name);

# Add the .xs file to the cleanup lists:
use Module::Build;
my $build = Module::Build->current;
$build->add_to_cleanup("$base_name.xs");

# working here - make the functions return their fitting values, and make
# the regexes store them. (Getting access to those stored parameter values,
# on the other hand, will take some work with Regex.pm itself.)

pp_addpm '# line ' . (__LINE__ + 2) . <<'FOR_MODULE';
 "MSER.pm.PL"
use PDL;
use Regex::Engine;

package Regex::Engine::MSER;
# An MSER condition base class:
use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter Regex::Engine::Quantified);

# Add functions to export
our @EXPORT = qw(MSER_const MSER_linear);

# working here - find a way to keep this from trying to export PP functions
# since they are only meant for internal use.

sub _init {
	my $self = shift;
	$self->SUPER::_init();
	
	# Check that explicit min and max quantifiers are reasonable:
	if ($self->{max_quant} !~ /%/ and $self->{max_quant} >= 0
			and $self->{max_quant} < $self->_min_length) {
		# This is considered an error, so throw an exception:
		my $name = $self->get_bracketed_name_string;
		(my $class_name = ref($self)) =~ s/.*:://;
		die "Error creating $class_name regex$name\n"
			."Explicit max quantifier was " . $self->{max_quant} . " but it must be larger than "
			. ($self->_min_length - 1) . "\n";
	}
	if ($self->{min_quant} !~ /%/ and $self->{min_quant} >= 0
			and $self->{min_quant} < $self->_min_length) {
		# This is considered an error, so throw an exception:
		my $name = $self->get_bracketed_name_string;
		(my $class_name = ref($self)) =~ s/.*:://;
		die "Error creating $class_name regex$name\n"
			."Explicit min quantifier was " . $self->{min_quant} . " but it must be larger than "
			. ($self->_min_length - 1) . "\n";
	}
	
	# Check that implicit min and max quantifiers are reasonable (not 0%):
	if ($self->{max_quant} =~ /%/) {
		# Strip off the percent sign:
		(my $percent = $self->{max_quant}) =~ s/%//;
		# Make sure it's not zero:
		if ($percent == 0) {
			my $name = $self->get_bracketed_name_string;
			(my $class_name = ref($self)) =~ s/.*:://;
			die "Error creating $class_name regex$name\n"
				."Percentage min quantifier must be larger than 0\%\n";
		}
	}
	if ($self->{min_quant} =~ /%/) {
		# Strip off the percent sign:
		(my $percent = $self->{max_quant}) =~ s/%//;
		# Make sure it's not zero:
		if ($percent == 0) {
			my $name = $self->get_bracketed_name_string;
			(my $class_name = ref($self)) =~ s/.*:://;
			die "Error creating $class_name regex$name\n"
				."Percentage min quantifier must be larger than 0\%\n";
		}
	}
}

# A minor extension to Quantified _prep that ensures the piddle is one or
# two dimensional. It is considered a fatal error if they try to run this
# regex on a higher-dimensional piddle.
sub _prep {
	my ($self, $piddle) = @_;
	die("You can only apply MSER conditions to one- or two-dimensional piddles\n")
		if $piddle->ndims > 2;
	return $self->SUPER::_prep($piddle);
}

# Constructor that can be utilized by all the derived MSER regex conditions.
sub _mser_new {
	my $class = shift;
	my $constructor_name = shift;
	
	croak("$constructor_name takes one or two optional arguments: $constructor_name([name], [quantifiers])")
		if @_ > 2;
	
	# Get the arguments:
	my ($name, $quantifiers);
	if (@_ == 2) {
		($name, $quantifiers) = @_;
		
		# Make sure they are what we expect:
		croak("Supplied two arguments to $constructor_name, but the first "
				. 'was not a name')
			if defined $name and ref($name) ne '';
		croak("Supplied two arguments to $constructor_name, but the second "
				. 'argument was not a two-element array reference')
			if defined $quantifiers
				and (ref($quantifiers) ne 'ARRAY' or @$quantifiers != 2);
	}
	elsif (@_ == 1) {
		if (not defined $_[0]) {
			# do nothing if it's not defined
		}
		elsif (ref($_[0]) eq '') {
			$name = $_[0];
		}
		elsif (ref ($_[0]) eq 'ARRAY') {
			croak("You supplied an array reference to $constructor_name with "
				. scalar(@{$_[0]}) . ' elements, but it must contain two elements')
				unless @{$_[0]} == 2;
			$quantifiers = $_[0];
		}
		else {
			croak("You supplied a single argument to $constructor_name, but "
				. " it is neither a name nor a two-element array reference\n"
				. "so I'm not sure what to do with it");
		}
	}
	$quantifiers = [$class->_min_length, -1] unless defined $quantifiers;
	
	# Create the subroutine regexp:
	return $class->new(quantifiers => $quantifiers
		, defined $name ? (name => $name) : ());
}

use PDL::NiceSlice;

package Regex::Engine::MSER::Const;
use strict;
use warnings;
our @ISA = qw(Regex::Engine::MSER);
use PDL::NiceSlice;

# We need at least two points for the MSER Const:
sub _min_length { 2 }

# working here - consider adding a field for which row to use, rather than
# defaulting to the first.

sub _to_stash {
	return qw(average), $_[0]->SUPER::_to_stash;
}

sub Regex::Engine::MSER::MSER_const {
	Regex::Engine::MSER::Const->_mser_new('MSER_const', @_);
}

sub _apply {
	my ($self, $left, $right) = @_;
	my $piddle = $self->{data};
	
	my $to_apply;
	if ($piddle->ndims == 1) {
		$to_apply = $piddle($left:$right);
	}
	else {
		$to_apply = $piddle($left:$right,0;-);
	}
	my ($length, $average, $variance) = $to_apply->_MSER_const_min_idx;
	
	return 0 if $length < $self->{min_size};
	
	return ($length->at(0), average => $average->at(0), variance => $variance->at(0));
}

package Regex::Engine::MSER::Linear;
use strict;
use warnings;
our @ISA = qw(Regex::Engine::MSER);

# we need at least three points for the MSER Linear:
sub _min_length { 3 }

sub Regex::Engine::MSER::MSER_linear {
	Regex::Engine::MSER::Linear->_mser_new('MSER_linear', @_);
}

sub _apply {
	my ($self, $left, $right) = @_;
	my $piddle = $self->{data};
	
	my ($x, $y);
	my ($length, $intercept, $slope, $variance);
	if ($piddle->ndims == 1) {
		($length, $intercept, $slope)
			= $piddle($left:$right)->_MSER_linear_min_idx_no_x;
	}
	else {
		my $y = $piddle($left:$right, 0;-);
		my $x = $piddle($left:$right, 1;-);
		($length, $intercept, $slope, $variance) = $x->_MSER_linear_min_idx($y);
	}
	
	# Fail if we did not match a large enough length:
	return 0 if $length < $self->{min_size};
	
	# Otherwise, return the length, slope and intercept:
	return ($length-at(0), slope => $slope->at(0)
		, intercept => $intercept->at(0), variance => $variance->at(0));
}

FOR_MODULE

pp_def('MSER_const_scores',
	Pars => 'y(n); [o] scores(n1)',
	# set n1 to be n - 1:
	RedoDimsCode => '$SIZE(n1) = $PDL(y)->dims[0] - 1;',
	Doc => 'Returns the scores for each point for a constant MSER scheme',
	Code => q{
		double S_y, S_yy, n_points;
		int i;
		
		threadloop %{
			S_y = $y(n => 0);
			S_yy = S_y*S_y;
			
			for(i = 1; i < $SIZE(n); i++) {
				/* Accumulate the sums */
				S_y += $y(n => i);
				S_yy += $y(n => i) * $y(n => i);
				
				n_points = i + 1;
				
				/* must omit spacing here thanks to PdlParObj.pm line 384 */
				$scores(n1 => i-1)
						= (S_yy - S_y * S_y / n_points) / i / n_points;
			}
			
		%}
	},
);


pp_def('_MSER_const_min_idx',
	Pars => 'y(n); int [o] best_index(); [o] best_avg(); [o] best_var()',
	Doc => '',
	Code => q{
		double S_y, S_yy, lowest_score, score, n_points, average;
		int i, best_index;
		best_index = 1;
		
		threadloop %{
			/* first point */
			S_y = $y(n => 0);
			S_yy = S_y*S_y;
			
			/* second point */
			S_y += $y(n => 1);
			S_yy += $y(n => 1) * $y(n => 1);
			
			/* first score */
			lowest_score = (S_yy - S_y * S_y / 2.) / 2.;
			
			/* record the average, variance, and index in case nothing later
			 * beats this one */
			$best_avg() = S_y / 2.;
			/* This is a special case: the score is the variance divided by
			 * the length, which is one in this case, so I can just use the
			 * lowest score here */
			$best_var() = lowest_score;
			$best_index() = 1;
			
			for(i = 2; i < $SIZE(n); i++) {
				/* Accumulate the sums */
				S_y += $y(n => i);
				S_yy += $y(n => i) * $y(n => i);
				
				n_points = i + 1;
				
				/* Compute the score */
				score = (S_yy - S_y * S_y / n_points) / n_points / i;
				if (score < lowest_score) {
					lowest_score = score;
					$best_index() = i;
					$best_avg() = S_y / n_points;
					$best_var() = score * i;
				}
			}
		%}
	},
);


# What follows is a bunch of C code with POD documentation interleaved in
# the comments. It uses a trick from ppport.h that allows me to use the
# exact same text in both the module and the XS source. It is also done in
# such a way that CPAN will only show the documentation. :-)

my $algorithm = <<'FOR_ALGORITHM';

#if 0
my $skip = <<'SKIP';
#endif

/*

=pod

=head2 Linear MSER

The basic premise for the MSER technique rests on the idea that we want to
find where the variance starts to strongly deviate from some consistent
value. We can just as easily work with the variance of the data from a
linear function as from a constant function, but care must be taken to keep
the algorithm efficient. For the linear MSER, we ask (1) what is the best
linear fit to the sequence of data up to this point, (2) how much does the
data vary with respect to that linear fit, and (3) at what point does the
MSER score, which is related to the variation scaled with respect to the
number of elements up to that point, obtain a minimum value?

=for details
The C function that I am about to define calculates the linear MSER scores
for each of a series of points. The values that it saves to memory and the
values that it uses for the x-positions depend on how you call the function.
You must provide the number of elements in your arrays (N) and the y-data
but you can pass 0 in for the x pointer as well as the scores pointer. If
you pass in zero for the x pointer, the tabulations will simply use the
increment in place of it. If you pass in an initialized array for scores, it
will store their results there; otherwise pass in a zero pointer. If you
pass in nonzero pointers for best_slope, best_intercept, or best_variance,
it will store the corresponding values at the dereferenced double. Under all
circumstances, it will return the index with the lowest score. All of this
will be explained throughout the rest of this documentation.

=cut

*/

int MSER_linear_score_calculator(double * xs, double * ys, double * scores
		, int N, double * best_slope, double * best_intercept
		, double * best_variance) {

/*

=pod

Calculating a least-squared-error linear fit for all points up to and
including the nth point is easy but I will go through the full calculation
here to make sure you know what's going on and so that I am sure all of my
equations are correct. The goal is to find the parameters that minimize this
sum:

 Sum = sum( ( Y(x_i) - y_i )^2 )

where the parameters are burried into the definition of Y(x):

 Y(x) = y0 + s * x.

Written out in full, I want to minimize this sum:

 Sum = sum( ( y0 + s * x_i - y_i )^2 )

Before going further, I will introduce a notation for the sums of the x- and
y-values:

 S_x = sum(x_i), S_xy = sum(x_i * y_i), etc.

Using this notation, the sum becomes:

 Sum = n * y0^2 + 2 * y0 * s * S_x - 2 * y0 * S_y
       + s^2 * S_xx - 2 * s * S_xy + S_yy

=for details
You can see the variable declarations for the just-named sums below, as well
as the slope and the intercept. In addition, I declare variables for x and
y, which makes a few things easier and cleaner, as well as variables to hold
the just-computed score and the overall lowest score. The variable n simply
holds the offset-plus-one, when it is used. I use the counting variable i
and store the index of the best score in the aptly named best_index
variable.

=cut

*/

	double S_x, S_y, S_xy, S_xx, S_yy, y0, s, x, y, score, lowest_score, n;
	int i, best_index;
	
	/* These are accumulators, so initialize them to zero */
	S_x = S_y = S_xx = S_xy = S_yy = 0;

	/* Compute the sums for the first three points */
	for(i = 0; i < 3; i++) {
		x = (xs ? xs[i] : i);
		y = ys[i];
		S_x += x;
		S_y += y;
		S_xy += x * y;
		S_xx += x * x;
		S_yy += y * y;
	}
	
/*

=pod

For the purposes of MSER scoring, I will declare the point that minimizes
C<Sum / n_i> to be the most likely candidate of the last point in the linear
fit. (As we will see later, C<n_i = i - 1>, as I will explain later.)

=for details
Put a bit more clearly, n_i = n_points - 2, as we'll see shortly.

To compute the value of C<y0> and C<s>, I need to take the derivative of the
squared sum with respect to the parameters C<y0> and C<s>:

 partial(sum)
 ------------ = 2 * n * y0 + 2 * s * S_x - 2 * S_y.
 partial(y0)

This needs to be set to zero, which means

 n * y0 + s * S_x - S_y = 0.

Now taking the derivative with respect to C<s> leads to this:

 partial(sum)
 ------------ = 2 * y0 * S_x + 2 * s * S_xx - 2 * S_xy
  partial(s)

which I again set to zero, obtaining

 y0 * S_x + s * S_xx - S_xy = 0.

Here are the two equations together:

 y0 * n   + s * S_x  - S_y  = 0,
 y0 * S_x + s * S_xx - S_xy = 0.

As we will see, these sums are cheap to compute and allow this method to run
in linear time. Two linear equations in two unknowns means that I can easily
compute C<y0> and C<s>. Let's first eliminate C<s> from these equations:

 y0 * n / S_x    + s - S_y / S_x   = 0,
 y0 * S_x / S_xx + s - S_xy / S_xx = 0.

Subtracting the second from the first leads to

 y0 * (n/S_x - S_x/S_xx) + S_xy/S_xx - S_y/S_x = 0,

which I can solve for C<y0> as

  ----------------------------
 |       S_y/S_x - S_xy/S_xx  |
 | y0 = --------------------- |
 |        n/S_x - S_x/S_xx    |
  ----------------------------

=cut

*/

	n = 3;
	
	/* Compute the first y-intercept */
	y0 = (S_y/S_x - S_xy/S_xx)
					/
		  (n/S_x - S_x/S_xx);
	
	/* Store the intercept, if requested */
	if (best_intercept) best_intercept[0] = y0;

/*

=pod

Once I have C<y0>, I can easily compute C<s>:

  ------------------------------
 | s = S_y / S_x - n * y0 / S_x |
  ------------------------------

=cut

*/

	/* Compute the first slope */
	s = S_y / S_x - n * y0 / S_x;
	/* Store the result if requested */
	if(best_slope) best_slope[0] = s;
	
/*

=pod

Finally, I can go back to compute the variance of the data with respect to
the fit. The variance is related to the sum that I just used to find the
parameters. Since the fit has two parameters, the number of degrees of
freedom should be C<n - 2>, where C<n> is the number of data points under
consideration. The MSER score is just this variance divided by the number of
degrees of freedom, so the score is

                      Sum
 score(n) = -----------------------
             ( n - 2 ) * ( n - 2 )

         -----------------------------------------------------------------
        |    n*y0^2 + 2*y0*s*S_x - 2*y0*S_y + s^2*S_xx - 2*s*S_xy + S_yy  |
        | = ------------------------------------------------------------- |
        |                         ( n - 2 )^2                             |
         -----------------------------------------------------------------

=cut

*/
	
	/* Compute the first score and store it, if appropriate */
	score = (n*y0*y0 + 2*y0*s*S_x - 2*y0*S_y + s*s*S_xx - 2*s*S_xy + S_yy)
			/ (n - 2) / (n - 2);
	
	lowest_score = score;
	best_index = i;
	
	if (scores) scores[0] = score;
	if (best_variance) best_variance[0] = score * (n - 2);

/*

=pod

So it is possible to compute each point's MSER for a linear fit to the data
in O(N) time, and in a single pass. I simply need to keep track of a
collection of sums, along with the minimum var/n and its corresponding index
n.

=cut

*/

	/* Loop over the remaining points */
	for(; i < N; i++) {
		x = (xs ? xs[i] : i);
		y = ys[i];
		S_x += x;
		S_y += y;
		S_xy += x * y;
		S_xx += x * x;
		S_yy += y * y;

		n = i + 1;
		
		/* Here are those equations again
		 ----------------------------
		|       S_y/S_x - S_xy/S_xx  |
		| y0 = --------------------- |
		|        n/S_x - S_x/S_xx    |
		 ----------------------------
		*/
		y0 = (S_y / S_x - S_xy / S_xx)
			/ (n / S_x - S_x / S_xx);
		/*
		 ------------------------------
		| s = S_y / S_x - n * y0 / S_x |
		 ------------------------------
		*/
		s = S_y / S_x - n * y0 / S_x;
		
		/* Compute the score and store it, as appropriate */
		/*
		 -----------------------------------------------------------------
		|    n*y0^2 + 2*y0*s*S_x - 2*y0*S_y + s^2*S_xx - 2*s*S_xy + S_yy  |
		| = ------------------------------------------------------------- |
		|                         ( n - 2 )^2                             |
		 -----------------------------------------------------------------
		*/
		score = ( n*y0*y0 + 2*y0*s*S_x - 2*y0*S_y + s*s*S_xx - 2*s*S_xy + S_yy)
				/ (n - 2) / (n - 2);
		
		if (score < lowest_score) {
			lowest_score = score;
			best_index = i;
			if(best_slope) best_slope[0] = s;
			if (best_intercept) best_intercept[0] = y0;
			if (best_variance) best_variance[0] = score * (n - 2);
		}
		
		if (scores) scores[i-2] = score;
	}
	
	return best_index;
}

#if 0
SKIP
#endif

FOR_ALGORITHM

pp_addhdr($algorithm);
pp_addpm($algorithm);

# Consider overriding PdlDoc for these...

pp_def('MSER_linear_scores_no_x',
	Pars => 'ys(n); [o] score(n2)',
	GenericTypes => ['D'],
	# set n2 to be n - 2:
	RedoDimsCode => '$SIZE(n2) = $PDL(ys)->dims[0] - 2;',
	Doc => 'Returns the scores for each point for a linear MSER scheme',
	Code => q{
		MSER_linear_score_calculator(0, $P(ys), $P(score), $SIZE(n), 0, 0, 0);
	},
);


pp_def('MSER_linear_scores',
	Pars => 'xs(n); ys(n); [o] score(n2)',
	GenericTypes => ['D'],
	# set n2 to be n - 2:
	RedoDimsCode => '$SIZE(n2) = $PDL(ys)->dims[0] - 2;',
	Doc => 'Returns the scores for each point for a linear MSER scheme',
	Code => q{
		MSER_linear_score_calculator($P(xs), $P(ys), $P(score), $SIZE(n), 0, 0, 0);
	},
);

pp_def('_MSER_linear_min_idx',
	Pars => 'xs(n); ys(n); int [o] best_index(); [o] slope(); [o] intercept(); [o] variance()',
	GenericTypes => ['D'],
	Doc => '',
	Code => q{
		$best_index() = MSER_linear_score_calculator($P(xs), $P(ys), 0, $SIZE(n)
				, $P(slope), $P(intercept), $P(variance));
	},
);

pp_def('_MSER_linear_min_idx_no_x',
	Pars => 'ys(n); int [o] best_index(); [o] slope(); [o] intercept(); [o] variance()',
	GenericTypes => ['D'],
	Doc => '',
	Code => q{
		$best_index() = MSER_linear_score_calculator(0, $P(ys), 0, $SIZE(n)
				, $P(slope), $P(intercept), $P(variance));
	},
);

pp_done;
