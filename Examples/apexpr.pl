#!/usr/bin/perl

use Parse::RecDescent;

use constant BIN_OP          => 1;
use constant FUNCTION_CALL   => 2;

use vars qw($GRAMMAR);
$GRAMMAR = <<END;
expression    : subexpression /^\$/  { \$return = \$item[1]; } 

subexpression : binary_op             { \$item[1] }
              | function_call         { \$item[1] }
              | var                   { \$item[1] }
              | literal               { \$item[1] }
              | '(' subexpression ')' { \$item[2] }
              | <error>

binary_op     : '(' subexpression op subexpression ')'
                { [ \$item[3][0], \$item[3][1], \$item[2], \$item[4] ] }

op            : />=?|<=?|!=|==/      { [ ${\BIN_OP},  \$item[1] ] }
              | /le|ge|eq|ne|lt|gt/  { [ ${\BIN_OP},  \$item[1] ] }
              | /\\|\\||or|&&|and/   { [ ${\BIN_OP},  \$item[1] ] }
              | /[-+*\\/\%]/         { [ ${\BIN_OP},  \$item[1] ] }

function_call : function_name '(' args ')'  
                { [ ${\FUNCTION_CALL}, \$item[1], \$item[3] ] }
              | function_name ...'(' subexpression
                { [ ${\FUNCTION_CALL}, \$item[1], [ \$item[3] ] ] }
              | function_name '(' ')'
                { [ ${\FUNCTION_CALL}, \$item[1] ] }

function_name : /[A-Za-z_][A-Za-z0-9_]*/
                { \$item[1] }

args          : <leftop: subexpression ',' subexpression>

var           : /[A-Za-z_][A-Za-z0-9_]*/  { \\\$item[1] }

literal       : /-?\\d*\\.\\d+/           { \$item[1] }
              | /-?\\d+/                  { \$item[1] }
              | <perl_quotelike>          { \$item[1][2] }

END


# create global parser
use vars qw($PARSER);
$PARSER = Parse::RecDescent->new($GRAMMAR);

# initialize preset function table
use vars qw(%FUNC);
%FUNC = 
  (
   'sprintf' => sub { sprintf(shift, @_); },
   'substr'  => sub { 
     return substr($_[0], $_[1]) if @_ == 2; 
     return substr($_[0], $_[1], $_[2]);
   },
   'lc'      => sub { lc($_[0]); },
   'lcfirst' => sub { lcfirst($_[0]); },
   'uc'      => sub { uc($_[0]); },
   'ucfirst' => sub { ucfirst($_[0]); },
   'length'  => sub { length($_[0]); },
   'defined' => sub { defined($_[0]); },
   'abs'     => sub { abs($_[0]); },
   'atan2'   => sub { atan2($_[0], $_[1]); },
   'cos'     => sub { cos($_[0]); },
   'exp'     => sub { exp($_[0]); },
   'hex'     => sub { hex($_[0]); },
   'int'     => sub { int($_[0]); },
   'log'     => sub { log($_[0]); },
   'oct'     => sub { oct($_[0]); },
   'rand'    => sub { rand($_[0]); },
   'sin'     => sub { sin($_[0]); },
   'sqrt'    => sub { sqrt($_[0]); },
   'srand'   => sub { srand($_[0]); },

   'glyph'   => sub { $_[0]->{'post'}{'STRINGS'}{$_[1]}; },
   'advance' => sub { $_[0]->{'hmtx'}{'advance'}[$_[1]]; },
   'xMin'    => sub { $_[0]->{'loca'}{'glyphs'}[$_[1]]{'xMin'}; },
   'yMin'    => sub { $_[0]->{'loca'}{'glyphs'}[$_[1]]{'yMin'}; },
   'xMax'    => sub { $_[0]->{'loca'}{'glyphs'}[$_[1]]{'xMax'}; },
   'yMax'    => sub { $_[0]->{'loca'}{'glyphs'}[$_[1]]{'yMax'}; } 
  );

sub _expr_evaluate {
  my ($tree, $vars, $FUNC) = @_;
  my ($op, $lhs, $rhs);

  # return literals up
  return $tree unless ref $tree;

  # lookup vars
  return $vars->{$$tree}
    if ref $tree eq 'SCALAR';

  my $type = $tree->[0];

  # handle binary expressions
  if ($type == BIN_OP) {
    ($op, $lhs, $rhs) = ($tree->[1], $tree->[2], $tree->[3]);

    # recurse and resolve subexpressions
    $lhs = _expr_evaluate($lhs, $vars, $FUNC) if ref($lhs);
    $rhs = _expr_evaluate($rhs, $vars, $FUNC) if ref($rhs);
    
    # do the op
    $op eq '==' and return $lhs == $rhs;
    $op eq 'eq' and return $lhs eq $rhs;
    $op eq '>'  and return $lhs >  $rhs;
    $op eq '<'  and return $lhs <  $rhs;

    $op eq '!=' and return $lhs != $rhs; 
    $op eq 'ne' and return $lhs ne $rhs;
    $op eq '>=' and return $lhs >= $rhs;
    $op eq '<=' and return $lhs <= $rhs;

    $op eq '+' and return $lhs + $rhs;
    $op eq '-' and return $lhs - $rhs;
    $op eq '/' and return $lhs / $rhs;
    $op eq '*' and return $lhs * $rhs;
    $op eq '%' and return $lhs %  $rhs;

    if ($op eq 'or' or $op eq '||') {
      # short circuit or
      $lhs = _expr_evaluate($lhs, $vars, $FUNC) if ref $lhs;
      return 1 if $lhs;
      $rhs = _expr_evaluate($rhs, $vars, $FUNC) if ref $rhs;
      return 1 if $rhs;
      return 0;
    } else {
      # short circuit and
      $lhs = _expr_evaluate($lhs, $vars, $FUNC) if ref $lhs;
      return 0 unless $lhs;
      $rhs = _expr_evaluate($rhs, $vars, $FUNC) if ref $rhs;
      return 0 unless $rhs;
      return 1;
    }

    $op eq 'le' and return $lhs le $rhs;
    $op eq 'ge' and return $lhs ge $rhs;
    $op eq 'lt' and return $lhs lt $rhs;
    $op eq 'gt' and return $lhs gt $rhs;
    
    confess("Error: unknown op: $op");
  }

  if ($type == FUNCTION_CALL) {
    croak("Error: found unknown subroutine call : $tree->[1]\n") unless exists($FUNC->{$tree->[1]});

    if (defined $tree->[2]) {
      return $FUNC->{$tree->[1]}->(
	 map { _expr_evaluate($_, $vars, $FUNC) } @{$tree->[2]}
      );
    } else {
      return $FUNC->{$tree->[1]}->();
    }
  }
}

sub evaluate
{
    my ($str, $vars, $FUNC) = @_;

    $tree = $PARSER->expression("($str)");
    return _expr_evaluate($tree, $vars, $FUNC);
}

use Font::TTF::Font;
use XML::SAX::Writer;
use XML::SAX::ParserFactory;
use Getopt::Std;

getopts('h');

unless ($ARGV[0] || $opt_h)
{
    pod2usage(1);
    exit;
}

if ($opt_h)
{
    pod2usage(-verbose => 2, -noperldoc => 1);
    exit;
}

my $f = Font::TTF::Font->open($ARGV[1]);
foreach (qw(loca post cmap hmtx))
{ $f->{$_}->read; }

my $writer = XML::SAX::Writer->new();
my $handler = SAX::Expr->new(Handler => $writer, 'font' => $f);
my $p = XML::SAX::ParserFactory->parser(Handler => $handler);
$p->parse_uri($ARGV[0]);

package SAX::Expr;

use base qw(XML::SAX::Base);

sub start_element
{
    my ($self, $el) = @_;
    my ($attrs) = $el->{'Attributes'};
    my ($gid) = $self->{'curr_gid'};
    my ($f) = $self->{'font'};

    if ($el->{'LocalName'} eq 'glyph')
    {
        $gid = $f->{'cmap'}->ms_lookup(hex($attrs->{'{}UID'}{'Value'})) if (defined $attrs->{'{}UID'});
        $gid = $f->{'post'}{'STRINGS'}{$attrs->{'{}PSName'}{'Value'}} if (defined $attrs->{'{}PSName'});
        $gid = $attrs->{'{}GID'}{'Value'} if (defined $attrs->{'{}GID'});
        $self->{'curr_gid'} = $gid;

        my ($vars) = {};
        my ($glyph) = $f->{'loca'}{'glyphs'}[$gid];
        if ($glyph)
        {
            $glyph->read;
            foreach (qw(xMin yMin xMax yMax))
            { $vars->{$_} = $glyph->{$_}; }
        }
        $vars->{'adv'} = $f->{'hmtx'}{'advance'}[$gid];
        $vars->{'font'} = $f;
        $self->{'vars'} = $vars;
    }
        
    foreach my $k (qw(x y value))
    {
        next unless (defined $attrs->{"{}$k"});
        $attrs->{"{}$k"}{'Value'} =~ s/^=(.*)$/main::evaluate($1, $self->{'vars'}, \%FUNC)/oe;
    }
        
    $self->SUPER::start_element($el);
}

__END__

=head1 TITLE

apexpr - evaluate expressions within an attachment point database

=head1 SYNOPSIS

  apexpr infile.xml infile.ttf

=cut