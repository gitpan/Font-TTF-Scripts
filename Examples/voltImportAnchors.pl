#! /usr/bin/perl
use strict;

our $VERSION="0.4, 2004-12-07";	#RMH
#   Add -i parameter
#our $VERSION="0.4, 2004-12-07";	#RMH
# Omit GLYPH field on Anchors where gdef has no NAME entry
#our $VERSION="0.3, 2003-11-14";	#RMH
# Display warnings from Font::Scripts::AP;
#our $VERSION="0.2, 2003-11-14";	#RMH
#	Require font for input -- eliminates dependency on GID field of AP database
#	Change to use Font::Scripts::AP -- permits AP by contour point

# 0.1   RMH    14-Aug-02     Import VOLT anchor definitions from XML

use Font::TTF::Font;
use Font::TTF::Scripts::AP;
use Getopt::Std;

our ($opt_d, $opt_i, $opt_l, $opt_s);
getopts("di:l:s");

unless (@ARGV == 3 || @ARGV == 4)
{
    die <<"EOT";

VOLTImportAnchors [-d] [-s] [-l alist.txt] [-i knownempty.txt] 
        in.ttf Anchors.xml out.ttf [out.vtp]

Imports anchor definitions from XML (in TTFBuilder syntax) into a VOLT project.

Original VOLT project must be a .TTF file (.VTP files no longer supported)
New anchor data, using TTFBuilder syntax, is read from Anchors.xml. A modified 
VOLT font project will be saved in out.ttf. If out.vtp is supplied, a copy of
the modified VOLT source is saved there.

Options:
    -d  discard existing VOLT anchor definitions that are not updated.

    -s  do not warn about existing VOLT anchor definitions that
        are not updated.

    -l  specifies a file that identifies which anchors to import. Anchors
        are listed on separate lines using the syntax:
            xml-anchor-type-name [, [volt-anchor-name] [, [component-num]]]
        A semicolon at start of line is a comment.
        For example:
            ; anchor list example. 
            ; XML anchor "vabove" will be imported directly
            ; "vbelow" will be renamed "BotCenter"
            ; "vbelow_2" will be renamed "BotCenter" but for component 2
            vabove
            vbelow,BotCenter
            vbelow_2,BotCenter,2
        If -l is not supplied, then all anchors will be imported and will
        be assumed to be for component 1 (no ligatures).
        (Note: the conversion between FontLab's convention of "_name" and
        VOLT's convention of "MARK_name" is automatic and should not be
        specified in a -l file).

    -i  specifies a file that identifies names of glyphs that are expected
        to have no outline. glyph names are supplied one per line.
        
$VERSION

EOT
}

my ($warningCount);

# Sub to print warning messages to console and log. 1st parm is the message.
# 2nd param, if supplied, is a line number (from the volt source).

sub MyWarn {
	my ($msg, $line) = @_;
	$warningCount++;
	if (defined $line) {
		print LOG "line $line: " . $msg;
		warn "line $line: " . $msg;
	} else {
		print LOG $msg;
		warn $msg;
	}
}


my ($inFont, $inXML, $outFont, $outSrc);	# Command line parameters


my ($Src, $SrcLine);	# Input VOLT source (slurped in as one long string), and line number counter
my $out;				# Output VOLT source

# If it is supplied the list file (-l parm) is read into a hash indexed by XML anchor type name,
# each element of which contains a two-element array consisting of the VOLT anchor name
# and the component number:
my (%XMLAnchorMap);

my %opts;           # Parameters to Font::TTF::Scripts::AP->read_font

# NB: The VOLT source parsing is stolen from VOLTFixup.

# For each GDEF record in the VOLT source, a structure
# is created using an anonymous hash. Gdef structures have these elements:
#
#    'NAME'
#    'ID'
#    '@UNICODES'    a referemce to an array of Unicode values
#				NB: for Glyph structures, these are Unicode values for the new font (i.e., from the cmap)
#				and for Gdef structures these are Unicode values from the old font (i.e., from the VOLT source)
#    'UNICODE' or 'UNICODEVALUES'  string values from the GDEF line (sans quote marks)
#    'TYPE'			string value from GDEF line
#    'COMPONENTS'	string value from GDEF line
#    'LINE'       linenumber from source
#
#and, if DEF_ANCHOR records are present:	
# 	 'ANCHORS' 	a hash containing:
#		name		the attachment point name, which yields an array, indexed by:
#			component	the component number (1, 2, etc), which yields a hash containing
#				'SRC'	the source record

#		
#
my (%GdefFromID, %GdefFromName, %GdefFromGdefUnicode);	

my $f;		# TTF font instance
my $numGlyphs;	# Number of glyphs in the TTF.

my $g;		# Reference to glyph structure
my $d;		# Reference to GDEF structure

my ($gid, $gname, $u);	# Glyph ID, Glyph name, and Unicode

my ($xName, $xAnchor);	# XML Anchor name, XML Anchor structure;

my ($vName, $vComponent, $vAnchor); 	# Volt Anchor name, Volt Anchor Component, Volt Anchor structure


my $xx;		# Temp variable

# Pick up command line parms:
($inFont, $inXML, $outFont, $outSrc) = @ARGV;

# Open logfile:
open (LOG, "> VoltImportAnchor.log") or die "Couldn't open 'VoltImportAnchor.log' for writing, stopping at";
print LOG "STARTING VOLTImportAnchors " . ($opt_d ? "-d " : "") . ($opt_s ? "-s " : "") . ($opt_l ? "-l $opt_l " : "") . "$inFont $inXML $outFont $outSrc\n\n";

# Parse -l list file if supplied
if ($opt_l) {
	open (IN, "<$opt_l") or die "Couldn't open '$opt_l' for reading.";
	while (<IN>) {
		s/[\r\n]*$//o;      # platform-safe chomp
		s/;.*$//o;          # Strip comments
		s/ //go;            # Strip whitespace
		my ($xName, $vName, $vComponent) = split(',');
		next if $xName eq '';
		$vName = $xName unless defined $vName;
		$vComponent = 1 unless defined $vComponent;
		$XMLAnchorMap{$xName} = [ $vName, $vComponent ];
		$XMLAnchorMap{"_$xName"} = [ "MARK_$vName", $vComponent ];
	}
	close IN;
}

# Parse -i file if supplied
if ($opt_i) {
    my @glist;
	open (IN, "<$opt_i") or die "Couldn't open '$opt_i' for reading.";
	while (<IN>) {
		s/[\r\n]*$//o;      # platform-safe chomp
		s/;.*$//o;          # Strip comments
		s/ //go;            # Strip whitespace
		next if $_ eq '';
		push @glist, $_;
	}
	close IN;
	$opts{'-knownemptyglyphs'} = join(',', @glist) if scalar(@glist);
}



# Sub to determine VOLT anchorname from an XML anchor "type" name; 
# Returns a list containing VOLT anchor name and component,
# or undef if we aren't to import this anchor.

sub ConvertXMLAnchorName {
	my ($xName, $xComponent);
	$xName = shift;
	
	if ($opt_l)
	{
		# -l supplied so do look; ignore any names we are to ignore:
		return undef unless exists $XMLAnchorMap{$xName};
		($xName, $xComponent) = @{$XMLAnchorMap{$xName}};
	}
	else
	{
		# -l not supplied: Assume we strip any trailing digits off as the component number:
		($xName, $xComponent) = ($xName =~ m/^(.*?)(\d*)$/);
		$xComponent ||= 1;
	}
	# adjust leading "_" to "MARK_":
	$xName =~ s/^_/MARK_/;
	# done!
	return ($xName, $xComponent);
}


# Read in font and anchor point data:

my $ap = Font::TTF::Scripts::AP->read_font($inFont, $inXML, %opts) || die "Can't read $inXML";
if (exists $ap->{'WARNINGS'})
{
	print LOG $ap->{'WARNINGS'};
	warn $ap->{'WARNINGS'};
	$warningCount += $ap->{'cWarnings'};
}
	

# Open and slurp VOLT source into $Src from existing font:

$f = $ap->{'font'};
exists $f->{'TSIV'} or die "Cannot find VOLT source table in file '$inFont'.\n";
$f->{'TSIV'}->read_dat;
$Src = $f->{'TSIV'}{' dat'};
$numGlyphs = $f->{'maxp'}{'numGlyphs'};

sub GetSrcLine {
	# Returns one line of text from the source, or undef if nothing left.
	# If the source was extracted from VOLT, the separators will be \r
	# If the source was read from CRLF delimited file, the separator will be \n
	# Need to allow either separator, but we don't return the terminator:
	return undef if $Src eq "";
	$SrcLine++;		# Keep track of line number in source.
	my $res;
	($res, $Src) = split (/\r|\n/, $Src, 2);
	return $res;
}



sub WriteAnchors {
	# Finally, here is the real work!
	#
	foreach $gid (0 .. $numGlyphs-1) {
		$d = $GdefFromID{$gid};

		# For each XML anchor definition, migrate location into GDEF structure, creating Anchor record if needed.
		if (defined $ap->{'glyphs'}[$gid]{'points'})
		{
			unless (defined $d)
			{
				MyWarn("attempt to import anchors on undefined glyph $gid");
				next;
			}
			foreach $xAnchor (values %{$ap->{'glyphs'}[$gid]{'points'}}) {
				$xName = $xAnchor->{'name'};
				($vName, $vComponent) = ConvertXMLAnchorName($xName);
				next unless defined $vName;
				$vAnchor = $d->{'ANCHORS'}{$vName}[$vComponent];
				if (defined $vAnchor) {
					# Edit existing anchor:
					$vAnchor->{'SRC'} =~ s/ POS .*END_POS /" POS DX $xAnchor->{'x'} DY $xAnchor->{'y'} END_POS "/e;
					$vAnchor->{'SRC'} =~ s/ AT / LOCKED AT / unless $vAnchor->{'SRC'} =~ / LOCKED /;
				} else {
					# Create new anchor:
					$d->{'ANCHORS'}{$vName}[$vComponent]{'SRC'} = "DEF_ANCHOR \"$vName\" ON $gid GLYPH "
						. (exists $d->{'NAME'} ? "$d->{'NAME'} " : "glyph$gid " )
						. "COMPONENT $vComponent LOCKED AT  POS DX $xAnchor->{'x'} DY $xAnchor->{'y'} END_POS END_ANCHOR";
					$vAnchor = $d->{'ANCHORS'}{$vName}[$vComponent];
				}
				# In any case, mark "dirty":
				$vAnchor->{'DIRTY'} = 1;
			}
		}
		
		# Now write out anchors for this glyph:
		next unless exists $d->{'ANCHORS'};
		foreach $vName (sort keys %{$d->{'ANCHORS'}}) {
			foreach $vComponent (0 .. @{$d->{'ANCHORS'}{$vName}}-1) {
				$vAnchor = $d->{'ANCHORS'}{$vName}[$vComponent];
				next unless $vAnchor->{'SRC'};
				unless ($vAnchor->{'DIRTY'})
				{
					if ($opt_d)
					{
						MyWarn ("Deleted anchor $vName,$vComponent on glyph $gid ($d->{'NAME'})\n") unless $opt_s;
						next;
					}
					MyWarn ("Didn't modify anchor $vName,$vComponent on glyph $gid ($d->{'NAME'})\n") unless $opt_s;
				}
				$out .= "$vAnchor->{'SRC'}\r";
			}
		}

	}
	
}

SRCLOOP: while (defined ($_ = GetSrcLine)) {

	if (/^DEF_ANCHOR /) {
		# need to modify anchordefs based on data from XML. A typical definition is:

		# DEF_ANCHOR "Below" ON 553 COMPONENT 1 LOCKED AT  POS DX 312 DY -540 END_POS END_ANCHOR

		# Note: Newer versions of VOLT include a glyph name:

		# DEF_ANCHOR "Below" ON 553 GLYPH gname COMPONENT 1 LOCKED AT  POS DX 312 DY -540 END_POS END_ANCHOR

		# The glyph name is not (currently) in quotes, but probably should be. This glyph name and the "ON"
		# glyph ID are mutually redundant with the DEF_GLYPH records, so why both? And what happens if
		# they disagree? Currently, the ON field is required (if it is absent, even if the GLYPH field
		# is present, VOLT resets the Anchor data to empty), so rather than risk an inconsistency I'm 
		# going to strip out the GLYPH field:

		# Anchor information is accumulated until
		# we have it all (so we can sort it)

		# For now, just add record to GDEF structure:
		
		($vName, $gid, $vComponent) = (m/DEF_ANCHOR (\S+).* ON (\d+) .* COMPONENT (\d+)/og);
		# make the quotes optional:
		$vName =~ s/^\"(.*)\"$/$1/;

		$GdefFromID{$gid}{'ANCHORS'}{$vName}[$vComponent]{'SRC'} = $_;
		next SRCLOOP;
	} 

	# PROCESS ALL OTHER KINDS OF LINES:

	if (/^GRID_PPEM/) {
		# Write out the anchor definitions (in sorted order: GID, Anchor name, component)
		WriteAnchors;
	}

	# Throw away any null bytes (typically at the end of the table):
	next SRCLOOP if /^\0+$/;
	
	# All other lines output as is...
	$out .= "$_\r";
	
	if (/^DEF_GLYPH/) {

		# PROCESS GDEF LINE:
		
		# extract important info from GDEF. Note the text lines are essentially in hash form already, e.g.:
		# DEF_GLYPH "U062bU062cIsol" ID 1097 UNICODE 64529 TYPE LIGATURE COMPONENTS 2 END_GLYPH
		# or
		# DEF_GLYPH "middot" ID 167 UNICODEVALUES "U+00B7,U+2219" TYPE BASE END_GLYPH
		# so it is easy to construct a hash:

		($xx = $_) =~ s/ END_GLYPH.*//;	# Remove end line sequence
		$xx =~ s/DEF_GLYPH/NAME/;		# Change DEF_GLYPH to NAME so we get correct structure variables
		$d = {split(' ', $xx)};			# Create GDEF structure
		$d->{'LINE'} = $SrcLine;

		# members of the hash at this point are:
		#	NAME	name of glyph
		#	ID		glyph ID
		#	UNICODE	decimal unicode value (optional), or
		#	UNICODEVALUES comma-separated list of Unicode values in U+nnnn string format
		#	TYPE	one of SIMPLE, MARK, or LIGATURE (optional)
		#	COMPONENTS	number of components in ligature (optional)
		#	LINE		line number from source


		if (not (exists $d->{'NAME'} and exists $d->{'ID'})) {
			MyWarn "Incomprehensible DEF_GLYPH\n", $SrcLine;
			next SRCLOOP;
		}
			
		# Some beta versions of VOLT didn't quote the glyph names, so let's make the quotes optional:
		$d->{'NAME'} =~ s/^\"(.*)\"$/$1/;

		$gname = $d->{'NAME'};
		$gid = $d->{'ID'};

		if (exists $GdefFromID{$gid}) {
			MyWarn "Glyph # $gid defined more than once in source -- second definition ignored\n", $SrcLine; 
			next SRCLOOP;
		};

 		# Coalesce UNICODE or UNICODEVALUES, if present, into @UNICODES array
		if (exists $d->{'UNICODE'}) {
			# Create array with one element:
			$d->{'@UNICODES'} = [ $d->{'UNICODE'} ];		
		} elsif (exists $d->{'UNICODEVALUES'}) {
			# Have to parse comma-separate list such as "U+00AF,U+02C9". But first get rid of quotes:
			$d->{'UNICODEVALUES'} =~ s/^\"(.*)\"$/$1/;
			$d->{'@UNICODES'} = [ map { hex (substr($_,2))} split (",", $d->{'UNICODEVALUES'})]; 
		}

		if ($gname =~ /^glyph\d+$/) {
			# GDEF includes a generic name -- we can only do so much at this point:
			$GdefFromID{$gid} = $d;							# Able to look up by GID
			if (exists $d->{'@UNICODES'}) {					# Able to lookup by Unicode
				foreach $u (@{$d->{'@UNICODES'}}) { $GdefFromGdefUnicode{$u} = $d;}
			}
			delete $d->{'NAME'};		# discard the generic name
			next SRCLOOP;
		}

		if (exists $GdefFromName{$gname}) {
			MyWarn "Glyph '$gname' defined more than once in source -- second definition ignored\n", $SrcLine;
			next SRCLOOP;
		}

		# Finally ... we can save this GDEF information
		$GdefFromID{$gid} = $d;								# Able to look up by GID
		$GdefFromName{$gname} = $d;							# Able to look up non-generic names only
		if (exists $d->{'@UNICODES'}) {						# Able to lookup by Unicode
			foreach (@{$d->{'@UNICODES'}}) { $GdefFromGdefUnicode{$_} = $d;}
		}		
		next SRCLOOP;
	} 

}			

# Write out new font:

# Insert the replacement source into the font
# Create, if it doesn't exist, the VOLT source table we are going to insert
$f->{'TSIV'} = Font::TTF::Table->new (PARENT => $f, NAME => 'TSIV') unless exists $f->{'TSIV'};

# Replace source:
$f->{'TSIV'}->{' dat'} = $out;

# Remove compiled tables if they exist:
for (qw( TSID TSIP TSIS )) { delete $f->{$_} };


$f->out($outFont);

if (defined $outSrc)
{
	# Open output source file:
	open (OUT, ">$outSrc") or die "Couldn't open '$outSrc' for writing.";
	print OUT $out;
	close OUT;
}


$xx = "\nFINISHED. ";
$xx .= ($warningCount > 0 ? $warningCount : "No") . " warning(s) issued. ";
print LOG $xx;
close LOG;

printf "%s%s\n", $xx, ($warningCount > 0) ? " See VoltImportAnchor.log for details." : "";

__END__

=head1 TITLE

voltImportAnchors - Imports anchor definitions from XML (in TTFBuilder syntax) into a VOLT project.

=head1 SYNOPSIS

  voltImportAnchors [-d] [-s] [-l alist.txt] in.ttf Anchors.xml out.ttf [out.vtp]

=head1 OPTIONS

  -d  discard existing VOLT anchor definitions that are not updated.
  -s  do not warn about existing VOLT anchor definitions that
      are not updated.
  -l  specifies a file that identifies which anchors to import.

=head1 DESCRIPTION

Original VOLT project must be a .TTF file (.VTP files no longer supported)
New anchor data, using TTFBuilder syntax, is read from Anchors.xml. A modified 
VOLT font project will be saved in out.ttf. If out.vtp is supplied, a copy of
the modified VOLT source is saved there.

For the C<-l> option, the file consist of a list of anchors to import which
are listed on separate lines using the syntax:

  xml-anchor-type-name [, [volt-anchor-name] [, [component-num]]]

A semicolon at start of line is a comment. For example:

    ; anchor list example. 
    ; XML anchor "vabove" will be imported directly
    ; "vbelow" will be renamed "BotCenter"
    ; "vbelow_2" will be renamed "BotCenter" but for component 2
    vabove
    vbelow,BotCenter
    vbelow_2,BotCenter,2

If C<-l> is not supplied, then all anchors will be imported and will
be assumed to be for component 1 (no ligatures). (Note: the conversion
between FontLab's convention of "_name" and VOLT's convention of "MARK_name"
is automatic and should not be specified in a -l file).

=head1 SEE ALSO

ttfbuilder, make_volt

=cut
