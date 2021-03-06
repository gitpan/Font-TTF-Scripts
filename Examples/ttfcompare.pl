#! /usr/bin/perl
use strict;
use Font::TTF::Font;
use Getopt::Std;
use Pod::Usage;

our ($opt_a, $opt_f, $opt_h, $opt_o, $opt_t, $opt_z, $VERSION);

getopts('afht:o:z:');

$VERSION = '0.3';  

unless ($#ARGV == 1 || defined $opt_h)
{
    pod2usage(1);
    exit;
}

if ($opt_h)
{
    pod2usage( -verbose => 2, -noperldoc => 1);
    exit;
}

=pod

=head1 TITLE

ttfcompare - Compare details of two fonts

=head1 SYNOPSIS

  ttfcompare [-a] [-f] [-o outfile] [-t table] [-z opts] font1 font2
  ttfcompare -h

=head1 OPTIONS

 -h       Show extended usage
 -a       Show all occurences per Name ID (name table only)
 -f       Display the full string instead of just 100 characters (name table only)
 -o file  Output to file instead of screen
 -t table What table to compare, identified by tag
 -z val   Some comparisons have options to control what is compared; see below.

=head1 DESCRIPTION

Compares values in the specified table between the two fonts and displays 
differences on screen. Currently works for name, cmap, hmtx and post tables only.  

If no table is specified, compares checksums and lengths of all tables.

With the name table, by default it shows just one per Name ID and the 
first 100 characters of each string

Values for -z are specific to tables being compared.
 
=cut

my %subs_table = ( name => \&namesub, post => \&postsub, cmap => \&cmapsub, hmtx => \&hmtxsub, x => \&csumsub ) ;

my ($font1, $font2) = @ARGV;
if ($opt_o) {
  unless (open (STDOUT, ">$opt_o")) {die ("Could not open $opt_o for output")} ;
}

$opt_t ||= 'x'; # If not supplied, just do table checksum/length
unless ($subs_table{$opt_t}) {die "Invalid table name '$opt_t'\n"}

# Open fonts and read the tables
my $f1 = Font::TTF::Font->open($font1) || die ("Couldn't open TTF '$font1'\n");
my $table1 = $f1->{$opt_t}->read unless $opt_t eq 'x';
my $f2 = Font::TTF::Font->open($font2) || die ("Couldn't open TTF '$font2'\n");
my $table2 = $f2->{$opt_t}->read unless $opt_t eq 'x';

# Produce output versions of font names without .ttf and padded to same length
my $if1 = index( $font1, ".ttf");
$if1 = $if1==-1 ? 0 : $if1;
my $if2 = index( $font2, ".ttf");
$if2 = $if2==-1 ? 0 : $if2;
my $maxif = $if1>=$if2 ? $if1 : $if2;
my $fname1 = substr ( $font1, 0, $if1 );
my $fname2 = substr ( $font2, 0, $if2 );
my $fpad1 = $fname1 . substr( "                ",0,$maxif-$if1);  
my $fpad2 = $fname2 . substr( "                ",0,$maxif-$if2);

# Run the subroutine based on the table name

$subs_table{$opt_t}->();

# Main subroutines - one for each table

sub namesub {

  my @namedesc = setnamedesc();
  my ($nid,$pid,$eid,$lid,$maxid1,$maxid2,$maxnid,$maxpid,$maxeid,@lkeys,$prevlid,$n1,$n2);
  
  # Loop round comparing values, allowing for some values only being in one of the name tables
  $maxid1 = $#{$table1->{'strings'}};
  $maxid2 = $#{$table2->{'strings'}};
  $maxnid = $maxid1 >= $maxid2 ? $maxid1 : $maxid2;
  
  NID: foreach $nid(0 .. $maxnid) {
    $maxid1 = $#{$table1->{'strings'}[$nid]};
    $maxid2 = $#{$table2->{'strings'}[$nid]};
    $maxpid = $maxid1 >= $maxid2 ? $maxid1 : $maxid2;
    foreach $pid (0 .. $maxpid) {
      $maxid1 = $#{$table1->{'strings'}[$nid][$pid]};
      $maxid2 = $#{$table2->{'strings'}[$nid][$pid]};
      $maxeid = $maxid1 >= $maxid2 ? $maxid1 : $maxid2;
      foreach $eid (0 .. $maxeid) {
        @lkeys = sort (  keys %{$table1->{'strings'}[$nid][$pid][$eid]},  keys %{$table2->{'strings'}[$nid][$pid][$eid]}  );
        $prevlid="";
        foreach $lid (@lkeys) {
          next if ($lid eq $prevlid); # @keys will have two copies of all keys that are in both name tables
          $prevlid = $lid;
          $n1 = $table1->{'strings'}[$nid][$pid][$eid]{$lid};
          $n2 = $table2->{'strings'}[$nid][$pid][$eid]{$lid};
          if ($n1 ne $n2) {
            print "Name ID: $nid";
            if ($namedesc[$nid]) {print " ($namedesc[$nid])";}
            print ", Platform ID: $pid, Encoding ID: $eid, Language ID: $lid \n";
            if (not $opt_f) {
              if (length($n1) > 100) {$n1 = substr ($n1,0,100)."...";}
              if (length($n2) > 100) {$n2 = substr ($n2,0,100)."...";}
            } 
            print "  $fpad1: $n1 \n";
            print "  $fpad2: $n2 \n\n";
            next NID if (not $opt_a);
          }
        }
      }
    }
  }
}

sub cmapsub {
    
  my @tables1 = $table1->{'Tables'};
  my $num1 = $table1->{'Num'};
  my @tables2 = $table2->{'Tables'};
  my $num2 = $table2->{'Num'};
  
  # Loop round to find matching tables, reporting any tables in only one of the fonts
  
  my $tab1 = 0;
  my $tab2 = 0;
  
  while ( $tab1<$num1 || $tab2 < $num2 ) {
    my $subt1 = @tables1[0]->[$tab1];
    my $subtest1 = &cmapsubtest($subt1); # Get value to check sub-tables are for same platform etc
    my $subt2 = @tables2[0]->[$tab2];
    my $subtest2 = &cmapsubtest($subt2);
    if ($subtest1 < $subtest2) {
      print "Sub-table only found in $fname1:\n";
      print "  Platform: $subt1->{'Platform'}, Encoding: $subt1->{'Encoding'}, Format: $subt1->{'Format'}\n";
      ++$tab1;
      next;
    }
    elsif ($subtest2 < $subtest1) {
      print "Sub-table only found in $fname2:\n";
      print "  Platform: $subt2->{'Platform'}, Encoding: $subt2->{'Encoding'}, Format: $subt2->{'Format'}\n";
      ++$tab2;
      next;
    } 
    print "Comparing sub-tables for:";
    print "  Platform: $subt1->{'Platform'}, Encoding: $subt1->{'Encoding'}, Format: $subt1->{'Format'}\n";
    my $val1 = $subt1->{'val'};
    my $val2 = $subt2->{'val'};
    my @codes = sort ( keys %{$val1},  keys %{$val2} );
    my $prevcode=0;
    my $difffound=0;
    my ($code,$g1,$g2);
    foreach $code (@codes) {
      next if ($code eq $prevcode); # @keys will have two copies of all keys that are in both name tables
      $prevcode = $code;
      $g1 = $val1->{$code};
      $g2 = $val2->{$code};
      if ($g1 ne $g2) {
        ++$difffound;
        #print ">$g1<\n";
        #print ">$g2<\n";
        $code = sprintf("%*X",6, $code);
        $g1 = $g1 eq "" ? "      " : sprintf ("%*d",6, $g1);
        $g2 = $g2 eq "" ? "      " : sprintf ("%*d",6, $g2);
        print "Code: $code,   $fname1 glyph: $g1,   $fname2 glyph: $g2\n";
      }
    }
    print "  $difffound differences found\n\n";
    ++$tab1;
    ++$tab2;
  }
}

sub postsub {

  my @pval1 = @{$table1->{'VAL'}};
  my @pval2 = @{$table2->{'VAL'}};
  
  my $difffound=0;
  my ($gnum,$gshow,$p1,$p2);
  foreach $gnum (0 .. 10) {
    $p1 = $pval1[$gnum];
    $p2 = $pval2[$gnum];
    if ($p1 ne $p2) {
      ++$difffound;
      $gshow = sprintf("%6d", $gnum);
      $p1 = $p1 eq "" ? "      " : sprintf ("%20s", $p1);
      $p2 = $p2 eq "" ? "      " : sprintf ("%20s", $p2);
      print "Glyph: $gshow,   $fname1: $p1,   $fname2: $p2\n";
    }
  } 
  print "  $difffound differences found\n\n";
}

sub csumsub {
  my %alltags;
  map { $alltags{$_}=1 } grep { length($_) == 4 } (keys(%{$f1}), keys(%{$f2}));
  my $difffound = 0;
  foreach my $tag (sort keys(%alltags))
  {
    if (!exists $f1->{$tag})
    {
      print "$tag  missing\n";
    }
    elsif (!exists $f2->{$tag})
    {
      print "$tag                   missing\n";
    }
    elsif ($f1->{$tag}{' CSUM'} != $f2->{$tag}{' CSUM'} || $f1->{$tag}{' LENGTH'} != $f2->{$tag}{' LENGTH'})
    {
      printf "%s  %8X / %-6d %8X / %-6d\n", $tag, $f1->{$tag}{' CSUM'}, $f1->{$tag}{' LENGTH'}, $f2->{$tag}{' CSUM'}, $f2->{$tag}{' LENGTH'};
    }
    else
    {
      next;
    }
    $difffound++;
  }
  print "  $difffound differences found\n\n";
}


=pod

For hmtx table, the -z value identifies what will be compared:

  bit 0:   lsb
  bit 1:   aw
  bit 2:   rsb
  bit 3:   xMin
  bit 4:   yMin
  bit 5:   xMax
  bit 6:   yMax
  bit 7:   numberOfContours

These values will be displayed left-to-right. If bit 8 is set, compare will allow up to difference of 3 in any value.

=cut 

sub hmtxsub {
  my (%gnames, $pstrings1, $pstrings2, $g1, $g2, $s1, $s2);
  my $difffound=0;
  my $maxlength;

  die "htmx compare requires post table\n" unless (exists($f1->{'post'}) && exists($f2->{'post'}));
  $pstrings1 = $f1->{'post'}->read->{'STRINGS'}; 
  $pstrings2 = $f2->{'post'}->read->{'STRINGS'};
  map {$maxlength = length($_) if $maxlength < length($_); $gnames{$_}=1} (keys %{$pstrings1}, keys %{$pstrings2});
  
  foreach my $gname (sort keys(%gnames))
  {
    unless (exists $pstrings1->{$gname})
    {
      printf "%-*s: missing\n", $maxlength, $gname;
      $difffound++;
      next;
    }
    unless (exists $pstrings2->{$gname})
    {
      printf "%-*s:                          | missing\n", $maxlength, $gname;
      $difffound++;
      next;
    }
    $g1 = $pstrings1->{$gname};
    $g2 = $pstrings2->{$gname};
    $s1 = $table1->cmpstring($g1, $opt_z);
    $s2 = $table2->cmpstring($g2, $opt_z);
    
    if ($opt_z && 0x100)
    {
      # Fuzzy compare -- allow differences of up to 3 units
      my (@s1, @s2);
      @s1 = split(/\s/, $s1);
      @s2 = split(/\s/, $s2);
      foreach (0 .. ($#s1 > $#s2 ? $#s1 : $#s2))
      {
        if (abs($s1[$_] - $s2[$_]) > 3)
        {
          printf "%-*s: %s\t| %s\n", $maxlength, $gname, $s1, $s2;
          $difffound++;
          last;
        }
      }
    }
    else
    {
      if ($s1 ne $s2) 
      {
        printf "%-*s: %s\t| %s\n", $maxlength, $gname, $s1, $s2;
        $difffound++;
      }
    }
  }
  print "  $difffound differences found\n\n";
}

# Other subroutines, called by main subroutines

sub cmapsubtest {
  # Creates value to compare cmap sub-tables to see if Platform, encoding and format match
  my $subtable = @_[0];
  my $p = $subtable->{'Platform'};
  my $e = $subtable->{'Encoding'};
  my $f = $subtable->{'Format'};
  my $ret = $p * 10000 + $e * 100 + $f;
  return $ret == 0 ? 999999 : $ret;
}

sub setnamedesc {
  my @namedesc;
  $namedesc[0] = "Copyright";
  $namedesc[1] = "Font Family";
  $namedesc[2] = "Font Subfamily";
  $namedesc[3] = "Unique identifier";
  $namedesc[4] = "Full font name";
  $namedesc[5] = "Version";
  $namedesc[6] = "Postscript name";
  $namedesc[7] = "Trademark";
  $namedesc[8] = "Manufacturer";
  $namedesc[9] = "Designer";
  $namedesc[10] = "Description";
  $namedesc[11] = "Vendor URL";
  $namedesc[12] = "Designer URL";
  $namedesc[13] = "License Description";
  $namedesc[14] = "License URL";
  $namedesc[15] = "Reserved";
  $namedesc[16] = "Preferred Family";
  $namedesc[17] = "Preferred Subfamily";
  $namedesc[18] = "Compatible Full";
  $namedesc[19] = "Sample text";
  $namedesc[20] = "PostScript CID findfont name";
  $namedesc[21] = "WWS Family Name";
  $namedesc[22] = "WWS Subfamily Name";
  return @namedesc;
  # The above could be simplified, but this self-documents the mapping from ID to string!
}


package Font::TTF::Hmtx;

sub cmpstring {
  my ($self, $gid, $optflag) = @_;
  unless (exists $self->{' glyphs'})
  {
    die "htmx compare requires loca table\n" unless exists $self->{' PARENT'}->{'loca'};
    $self->{' glyphs'} = $self->{' PARENT'}{'loca'}->read->{'glyphs'};
  }
  $self->{' glyphs'}[$gid]->read if defined $self->{' glyphs'}[$gid];
  my @vals = (
    $self->{'lsb'}[$gid],       # 0 
    $self->{'advance'}[$gid],   # 1 
    $self->{' glyphs'}[$gid]{'xMax'} - $self->{'advance'}[$gid],  # 2 
    $self->{' glyphs'}[$gid]{'xMin'},   # 3 
    $self->{' glyphs'}[$gid]{'xMax'},   # 4 
    $self->{' glyphs'}[$gid]{'yMin'},   # 5 
    $self->{' glyphs'}[$gid]{'yMax'},   # 6 
    $self->{' glyphs'}[$gid]{'numberOfContours'},   # 7 
    );
    
  $optflag ||= 3; # default to comparing lsb & aw
  
  my $res;
  return join(' ', @vals[grep {$optflag & (1<<$_)} (0..7)]);
}

=head1 BUGS

None known

=head1 AUTHOR

Martin Hosken L<http://scripts.sil.org/FontUtils>.
(see CONTRIBUTORS for other authors).

=head1 LICENSING

Copyright (c) 1998-2014, SIL International (http://www.sil.org)

This script is released under the terms of the Artistic License 2.0.
For details, see the full text of the license in the file LICENSE.

=cut
