#! perl
foreach $f (qw(add_classes check_attach dumpfont eurofix fret hackos2 make_gdl make_volt psfix sfd2ap ttf2volt ttfbboxfix ttfbuilder ttfdeflang ttfname ttfremap ttfsetver ttftable volt2ap volt2ttf))
{
    if ($ARGV[0] eq '-r')
    {
        unlink "$ARGV[1]\\$f.bat";
    }
    else
    {
        open(FH, "> $ARGV[0]\\$f.bat") || die $@;
        print FH "@\"$ARGV[0]\\parl.exe\" \"$ARGV[0]\\fontutils.par\" $f %1 %2 %3 %4 %5 %6 %7 %8 %9\n";
        close(FH);
    }
}
