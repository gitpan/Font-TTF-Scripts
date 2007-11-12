#!/usr/bin/perl
use IO::File;

if ($ARGV[0])
{
    my ($fh) = IO::File->new($ARGV[0]);
    while (<$fh>)
    { $text .= $_; }
    $fh->close;
    parse($text);
}

sub parse
{
    my ($str) = @_;
    my ($res);

    $str =~ m/^\x{FEFF}?\s*/og;
    $str .= " ";        # ensure final space to match

#    glyph : 'DEF_GLYPH' <commit> qid 'ID' num glyph_unicode(?) glyph_type(?) glyph_component(?) 'END_GLYPH'
#            { 
#                $dat{'glyphs'}[$item[5]] = {'uni' => $item[6][0], 'type' => $item[7][0], 'name' => $item[3], #'component_num' => $item[8][0], 'gnum' => $item[5]};
#                $dat{'glyph_names'}{$item[3]} = $item[5];
#                1;
#            }
#
#    glyph_unicode : 'UNICODEVALUES' <commit> '"' uni_list '"' 
#            { $return = [map {s/^U+//oi; hex($_);} split(/\s*,\s*/, $item[-2])]; }
#                  | 'UNICODE' num
#            { $return = [$item[-1]]; }
#
#    glyph_type : 'TYPE' /MARK|BASE|LIGATURE/
#            { $return = $item[2]; }
#
#    glyph_component : 'COMPONENTS' num
#            { $return = $item[-1]; }
#
    while ($str =~ m/\GDEF_GLYPH\s+"([^"]+)"\s+ID\s+(\d+)\s+(?:(?:UNICODEVALUES\s+"([^"]+)")|(?:UNICODE\s+(\d+))\s+)?(?:TYPE\s+(MARK|BASE|LIGATURE)\s+)?(?:COMPONENTS\s+(\d+)\s+)?END_GLYPH\s+/ogc)
    {
        my ($name, $gnum, $uni_list, $uni, $type, $comp) = ($1, $2, $3, $4, $5, $6);
        
        $res->{'glyphs'}[$gnum] = {'name' => $name, 
                'gnum' => $gnum,
                'component_num' => $comp,
                'type' => $type};
        if ($uni_list)
        { $res->{'glyphs'}[$gnum]{'uni'} = [map {s/^U+//oi; hex($_);} split(/\s*,\s*/, $uni_list)]; }
        else
        { $res->{'glyphs'}[$gnum]{'uni'} = [$uni]; }
        $res->{'glyph_names'}{$name} = $gnum;
    }

#    script : 'DEF_SCRIPT' <commit> name tag langsys(s?) 'END_SCRIPT'
#            { $dat{'scripts'}{$item[3]} = {'tag' => $item[4], 'lang' => $item[5]}; }
    while ($str =~ m/\GDEF_SCRIPT\s+NAME\+"([^"]+)"\s+TAG\s+"([^"]+)"\s+/ogc)
    {
        my ($name, $tag) = ($1, $2);
        my (@langs);

#    langsys : 'DEF_LANGSYS' name tag feature(s?) 'END_LANGSYS'
#            { $return = { 'name' => $item[2], 'tag' => $item[3], map {$_->{'name'} => $_} @{$item[4]}}; }
        while ($str =~ m/\GDEF_LANGSYS\s+NAME\+"([^"]+)"\s+TAG\s+"([^"]+)"\s+/ogc)
        {
            my ($lname, $ltag) = ($1, $2);
            my (%feats);

#    feature : 'DEF_FEATURE' name tag lookup_ref(s?) 'END_FEATURE'
#            { $return = { 'name' => $item[2], 'tag' => $item[3], 'lookups' => $item[4]}; }
            while ($str =~ m/\GDEF_FEATURE\s+NAME\+"([^"]+)"\s+TAG\s+"([^"]+)"\s+/ogc)
            {
                my ($fname, $ftag) = ($1, $2);
                my (@lkups);

#    lookup_ref : 'LOOKUP' qid
#        { $return = $item[2]; }
                while ($str =~ m/\GLOOKUP\s+"([^"]+)"\s+/ogc)
                {
                    my ($kname) = ($1);
                    push (@lkups, $kname);
                }
                $feats{$fname} = {'name' => $fname, 'tag' => $ftag, 'lookups' => [@lkups]};

                unless ($str =~ m/\GEND_FEATURE\s+/ogc)
                { die "Expected END_FEATURE, found: " . substr($str, pos($str), 20); }
            }
            push (@langs, {'name' => $lname, 'tag' => $ltag, %feats});

            unless ($str =~ m/\GEND_LANGSYS\s+/ogc)
            { die "Expected END_LANGSYS, found: " . substr($str, pos($str), 20); }
        }

        $res->{'scripts'}{$name} = {'tag' => $tag, 'lang' => [@langs]};
        unless ($str =~ m/\GEND_SCRIPT\s+/ogc)
        { die "Expected END_SCRIPT, found: " . substr($str, pos($str), 20); }
    }

#    group : 'DEF_GROUP' <commit> qid enum(?) 'END_GROUP'
#            { $dat{'groups'}{$item[3]} = $item[4][0]; }
    while ($str =~ m/\GDEF_GROUP\s+"([^"]+)"\s+(?:ENUM\s+)?/ogc)
    {
        my ($name) = ($1);
        my (@entries) = parse_enum(\$str, $dat);
        $res->{'groups'}{$name} = [@entries];
        unless ($str =~ m/\G(?:END_ENUM\s+)?END_GROUP\s+/ogc)
        { die "Expected END_GROUP, found: " . substr($str, pos($str), 20); }
    }

#    lookup : 'DEF_LOOKUP' <commit> qid lk_procbase(?) lk_procmarks(?) lk_all(?) lk_direction(?) lk_context(s) # lk_content
#            { push (@{$dat{'lookups'}}, { 'id' => $item[3],
#                                          'base' => $item[4][0],
#                                          'marks' => $item[5][0],
#                                          'all' => $item[6][0],
#                                          'dir' => $item[7][0],
#                                          'contexts' => [@{$item[8]}],
#                                          'lookup' => $item[9] }); }
#    lk_procbase : /SKIP_BASE|PROCESS_BASE/
#
#    lk_procmarks : /PROCESS_MARKS|SKIP_MARKS/
#
#    lk_all : 'ALL' | qid
#            { $return = $item[1] || $item[2]; }
#
#    lk_direction : 'DIRECTION' /LTR|RTL/            # what about RTL here?
#            { $return = $item[2]; }
#
    while ($str =~ m/\GDEF_LOOKUP\s+"([^"]+)"\s+(?:(SKIP_BASE|PROCESS_BASE)\s+)?(?:(SKIP_MARKS|PROCESS_MARKS)\s+)?(?:(?:(ALL)|"([^"]+)")\s+)?(?:DIRECTION\s+(LTR|RTL)\s+)?/ogc)
    {
        my ($name) = $1;
        push (@{$res->{'lookups'}}, {'id' => $1,
                'base' => $2,
                'marks' => $3,
                'all' => $4 || $5,
                'dir' => $6});

#    lk_context : 'IN_CONTEXT' lk_context_lt(s?) 'END_CONTEXT'
#            { $return = [@{$item[2]}]; }
        while ($str =~ m/\GIN_CONTEXT\s+/ogc)
        {
            my (@context);

#    lk_context_lt : /LEFT|RIGHT/ context(s)
#            { $return = [$item[1], @{$item[-1]}]; }
            while ($str =~ m/\g(RIGHT|LEFT)\s+/ogc)
            { push (@context, [$1, parse_enum(\$str, $res)]); }

            unless ($str =~ m/\GEND_CONTEXT\s+/ogc)
            { die "Expected END_CONTEXT, found: " . substr($str, pos($str), 20); }

            push (@{$res->{'lookups'}[-1]{'contexts'}}, [@context]);
        }

#    lk_content : lk_subst | lk_pos
#            { $return = $item[1] || $item[2]; }
#
#    lk_subst : 'AS_SUBSTITUTION' subst(s) 'END_SUBSTITUTION'
#            { $return = ['sub', $item[2]]; }
#
#    lk_pos : 'AS_POSITION' post(s) 'END_POSITION'
#            { $return = ['pos', $item[2]]; }
        while ($str =~ m/\G(AS_SUBSTITUTION|AS_POSITION)\s+/ogc)
        {
            my ($type) = $1;
            my (@content);

            if ($type eq 'AS_SUBSTITUTION')
            {
#    subst : 'SUB' context(s?) 'WITH' context(s?) 'END_SUB'
#            { $return = [$item[2], $item[4]]; }
                while ($str =~ m/\GSUB\s+/ogc)
                {
                    my (@in) = parse_enum(\$str, $res);
                    my (@out);
                    unless ($str =~ m/\GWITH\s+/ogc)
                    { die "Expected WITH in LOOKUP $name, found: " . substr($str, pos($str), 20); }
                    @out = parse_enum(\$str, $res);
                    unless ($str =~ m/\GEND_SUB\s+/ogc)
                    { die "Expected END_SUB in LOOKUP $name, found: " . substr($str, pos($str), 20); }
                    push (@content, [[@in], [@out]]);
                }
                push (@{$res->{'lookups'}[-1]{'lookup'}}, ['sub', [@content]]);

                unless ($str =~ m/\GEND_SUBSTITUTION\s+/ogc)
                { die "Expected END_SUBSTITUION in LOOKUP $name, found: " . substr($str, pos($str), 20); }
            }
            else        # presume pos
            {
                while (1)
                {
#    post : 'ATTACH_CURSIVE' <commit> exit_con(s) enter_con(s) 'END_ATTACH'
#            { $return = {'type' => $item[1], 'exits' => $item[3], 'enters' => $item[4] }; }
                    if ($str =~ m/\GATTACH_CURSIVE\s+/ogc)
                    {
                        my (@exits, @enters);
#    exit_con : 'EXIT' context
#            { $return = $item[-1]; }
                        while ($str =~ m/\GEXIT\s+/ogc)
                        {
                            my (@e) = parse_enum(\$str, $res);
                            push (@exits, $e[0]);
                        }
#    enter_con : 'ENTER' context
#            { $return = $item[-1]; }
                        while ($str =~ m/\GENTER\s+/ogc)
                        {
                            my (@e) = parse_enum(\$str, $res);
                            push (@enters, $e[0]);
                        }
                        push (@content, {'type' => 'ATTACH_CURSIVE', 'exits' => [@exits], 'enters' => [@enters]});
                        unless ($str =~ m/\GEND_ATTACH\s+/ogc)
                        { die "Expected END_ATTACH in LOOKUP $name, found: " . substr($str, pos($str), 20); }
                    }
#        | 'ATTACH' <commit> context(s) 'TO' attach(s) 'END_ATTACH'
#            { $return = {'type' => $item[1], 'context' => $item[3], 'to' => $item[5] }; }
                    elsif ($str =~ m/\GATTACH\s+/ogc)
                    {
                        my (@anchors);
                        my (@cont) = parse_enum(\$str, $res);
                        unless ($str =~ m/\GTO\s+/ogc)
                        { die "Expected TO in LOOKUP $name, found: " . substr($str, pos($str), 20); }
#    attach : context 'AT' 'ANCHOR' qid
#            { $return = [$item[1], $item[-1]]; }
                        while (1)
                        {
                            my (@acont) = parse_enum(\$str, $res);
                            last unless (@acont);
                            if ($str =~ m/\GAT\s+ANCHOR\s+"([^"]+)"\s+/ogc)
                            { push (@anchors, [$acont[0], $1]); }
                            else
                            { die "Expected AT ANCHOR in LOOKUP $name, found: " . substr($str, pos($str), 20); }
                        }
                        push (@content, {'type' => 'ATTACH', 'context' => [@cont], 'to' => [@anchors]});
                        unless ($str =~ m/\GEND_ATTACH\s+/ogc)
                        { die "Expected END_ATTACH in LOOKUP $name, found: " . substr($str, pos($str), 20); }
                    }
#        | 'ADJUST_PAIR' <commit> post_first(s) post_second(s) post_adj(s) 'END_ADJUST'
#            { $return = {'type' => $item[1], 'context1' => $item[3], 'context2' => $item[4], 'adj' => $item[5]}; }
                    elsif ($str =~ m/\GADJUST_PAIR\s+/ogc)
                    {
                        my (@firsts, @seconds, @adjs);

#    post_first : 'FIRST' context
#            { $return = $item[-1]; }
                        while ($str =~ m/\GFIRST\s+/ogc)
                        {
                            my (@e) = parse_enum(\$str, $res);
                            push (@firsts, $e[0]);
                        }

#    post_second : 'SECOND' context
#            { $return = $item[-1]; }
                        while ($str =~ m/\GSECOND\s+/ogc)
                        {
                            my (@e) = parse_enum(\$str, $res);
                            push (@seconds, $e[0]);
                        }

#    post_adj : num num 'BY' pos(s)
#            { $return = [$item[1], $item[2], $item[4]]; }
                        while ($str =~ m/\G(\d+)\s+(\d+)\s+BY\s+/ogc)
                        {
                            my ($l, $r) = ($1, $2);
                            my ($pos, @poses);
                            while ($pos = parse_pos(\$str))
                            { push (@poses, $pos); }
                            push (@adjs, [$l, $r, [@poses]]);
                        }
                        push (@content, {'type' => 'ADJUST_PAIR',
                                'context1' => [@firsts],
                                'context2' => [@seconds],
                                'adj' => [@adjs]});
                        unless ($str =~ m/\GEND_ADJUST\s+/ogc)
                        { die "Expected END_ADJUST in LOOKUP $name, found: " . substr($str, pos($str), 20); }
                    }
#        | 'ADJUST_SINGLE' <commit> post_single(s) 'END_ADJUST'
#            { $return = {'type' => $item[1], 'context' => [map {$_->[0]} @{$item[3]}], 'adj' => [map {$_->[1]} @{$item[3]}]}; }
                    elsif ($str =~ m/\GADJUST_SINGLE\s+/ogc)
                    {
                        my (@contexts, @adjs, @e);

#    post_single : context 'BY' pos
#            { $return = [$item[1], $item[3]]; }
                        while (@e = parse_enum(\$str, $res))
                        {
                            my ($pos);

                            push (@contexts, $e[0]);
                            if ($pos = parse_pos(\$str))
                            { push (@adjs, $pos); }
                            else
                            { die "Expected POS in LOOKUP $name, found: " . substr($str, pos($str), 20); }
                        }
                        push (@content, {'type' => 'ADJUST_SINGLE', 'context' => [@contexts],
                                        'adj' => [@adjs]});
                        unless ($str =~ m/\GEND_ADJUST\s+/ogc)
                        { die "Expected END_ADJUST in LOOKUP $name, found: " . substr($str, pos($str), 20); }
                    }
                    else
                    { last; }
                }
                unless ($str =~ m/\GEND_POSITION\s+/ogc)
                { die "Expected END_POSITION in LOOKUP $name, found: " . substr($str, pos($str), 20); }
            }
        }
    }

#    anchor : 'DEF_ANCHOR' <commit> qid 'ON' num 'GLYPH' gid 'COMPONENT' num anchor_locked(?) 'AT' pos 'END_ANCHOR'
#            { $dat{'glyphs'}[$item[5]]{'anchors'}{$item[3]} = {'pos' => $item[-2], 'component' => $item[9], 'locked' => $item[10][0]}; 1; }
#    
#    anchor_locked : 'LOCKED'
    while ($str =~ m/\GDEF_ANCHOR\s+"([^"]+)"\s+ON\s+(\d+)\s+GLYPH\s+(?:(?:"([^"]+)")|(\S+))\s+COMPONENT\s+(\d+)\s+(?:(LOCKED)\s+)?AT\s+/ogc)
    {
        my ($name, $gnum, $gname, $comp, $locked) = ($1, $2, $3 || $4, $5, $6);
        my ($pos) = parse_pos(\$str);

        unless ($pos)
        { die "Expected POS in ANCHOR $name on $gname, found: " . substr($str, pos($str), 20); }
        $res->{'glyphs'}[$gnum]{'anchors'}{$name} = {'pos' => $pos, 'component' => $comp, 'locked' => $locked};
    }

#    info : i_grid(?) i_pres(?) i_ppos(?) i_cmap(s?)
#            { $dat{'info'} = {
#                    grid => $item[1][0],
#                    present => $item[2][0],
#                    ppos => $item[3][0],
#                    cmap => $item[4] };
#            }
#    
#    i_grid : 'GRID_PPEM' num
#    
#    i_pres : 'PRESENTATION_PPEM' num
#    
#    i_ppos : 'PPOSITIONING_PPEM' num
#    
#    i_cmap : 'CMAP_FORMAT' num num num
#            { $return = [$item[2], $item[3], $item[4]]; }

    if ($str =~ m/\GGRID_PPEM\s+(\d+)\s+/ogc)
    { $res->{'info'}{'grid'} = $1; }

    if ($str =~ m/\GPRESENTATION_PPEM\s+(\d+)\s+/ogc)
    { $res->{'info'}{'present'} = $1; }

    if ($str =~ m/\GPOSITIONING_PPEM\s+(\d+)\s+/ogc)
    { $res->{'info'}{'ppos'} = $1; }

    if ($str =~ m/\GCMAP_FORMAT\s+(\d+)\s+(\d+)\s+(\d+)\s+/ogc)
    { $res->{'info'}{'cmap'} = [$1, $2, $3]; }

    return $res;
}

sub parse_enum
{
    my ($str, $dat) = @_;
    my (@res);

#    context : 'GLYPH' <commit> gid   { $return = [$item[1], $item[3]]; }
#             | 'GROUP' <commit> qid  { $return = [$item[1], $item[3]]; }
#             | 'RANGE' <commit> gid 'TO' gid   { $return = [$item[1], $item[3], $item[5]]; }
#             | enum                 { $return = ['ENUM', @{$item[1]}]; }
    while (1)
    {
        if ($$str =~ m/\GGLYPH\s+(?:"([^"]+)"|(\S+))\s+/ogc)
        { push (@res, ['GLYPH', $dat->{'glyph_names'}{$1 || $2}]); }
        elsif ($$str =~ m/\GGROUP\s+"([^"]+)"\s+/ogc )
        { push (@res, ['GROUP', $1]); }
        elsif ($$str =~ m/\GRANGE\s+(?:"([^"]+)"|(\S+))\s+TO\s+(?:"([^"]+)"|(\S+))\s+/ogc)
        { push (@res, ['RANGE', $dat->{'glyph_names'}{$1 || $2}, $dat->{'glyph_names'}{$3 || $4}]); }
        elsif ($$str =~ m/\GENUM\s+/ogc)
        {
            push (@res, ['ENUM', [parse_enum($$str, $dat)]]);
            unless ($$str =~ m/\GEND_ENUM\s+/ogc)
            { die "Expected END_ENUM, found: " . substr($$str, pos($$str), 20); }
        }
        else
        { last; }
    }
    @res;
}

sub parse_pos
{
    my ($str) = @_;
    my ($res) = {};

#    pos : 'POS' pos_adv(?) pos_dx(?) pos_dy(?) 'END_POS'
#            { $return = {
#                    'adv' => $item[2][0],
#                    'x' => $item[3][0],
#                    'y' => $item[4][0] }; }
#

    return undef unless ($$str =~ m/\GPOS\s+/ogc);

#    pos_dx : 'DX' <commit> num pos_adj(s?)
#            { $return = [$item[3], $item[4]]; }
    if ($$str =~ m/\GDX\s+(\d+)\s+/ogc)
    {
        my ($val) = $1;
        my (@adjs) = parse_adjs($str);
        $res->{'x'} = [$val, [@adjs]];
    }

#    pos_dy : 'DY' <commit> num pos_adj(s?)
#            { $return = [$item[3], $item[4]]; }
    if ($$str =~ m/\GDY\s+(\d+)\s+/ogc)
    {
        my ($val) = $1;
        my (@adjs) = parse_adjs($str);
        $res->{'y'} = [$val, [@adjs]];
    }

#    pos_adv : 'ADV' <commit> num pos_adj(s?)
#            { $return = [$item[3], $item[4]]; }
    if ($$str =~ m/\GADV\s+(\d+)\s+/ogc)
    {
        my ($val) = $1;
        my (@adjs) = parse_adjs($str);
        $res->{'adv'} = [$val, [@adjs]];
    }

    unless ($$str =~ m/\GEND_POS\s+/ogc)
    { return warn "Expected END_POS\n"; }

    return $res;
}

sub parse_adjs
{
    my ($str) = @_;
    my (@res);

#    pos_adj : 'ADJUST_BY' <commit> num 'AT' num
#            { $return = [$item[3], $item[5]]; }

    while ($$str =~ m/\GADJUST_BY\s+(\d+)\s+AT\s+(\d+)\s+/ogc)
    { push (@res, [$1, $2]); }
    return @res;
}

