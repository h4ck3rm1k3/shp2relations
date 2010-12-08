use strict;
use warnings;
use Data::Dumper;
use Carp;

my $tolerance=20;
my %nodes;
my %replace; # replace these ids with these
my %nodeids; # lookup the latlon of the nodes
my %nodesways; # what ways are these nodes used in
my %tags; # store the tags

my $newids = -3000000; # we give new objects ids starting here
my $current_way;
my $debug=1;

#my $current_parent_way; # when we split the way, keep track of where they came from

# reprocessing 
# we need to store all the ways after the first pass because we dont want to have to cut a way twice.
# 

sub emitstring
{
    my $s=shift;
    # get the string
    # print it 
}


my $skip=0;

sub begin_way
{
    my $id=shift;
    $current_way = $id;
    $skip=0;
}

sub end_way
{
    $current_way=undef;
}

sub checksum
{
    my $lat=shift;
    my $lon=shift;
    my $checksum =(($lat + 180) *100000000000) + (($lon + 180) *1000000);
    return int($checksum);
}

sub postprocess_node_in_way
{
    my $id=shift;
#    my $coords=$nodeids{$id};
#    warn Dumper($coords);
#    die "no coords for $id" unless $coords;


#    my ($lat,$lon) =@{$coords};
#    my $checksum = checksum($lat,$lon);
#    $current_way->{checksum} += $checksum;
#    $current_way->{checksum} += 
}


my %ways;

# # the way.
# sub split_way
# {
#     my $id=shift; # the splitting node

#     
#     $current_parent_way=$current_way;
#     $current_way = $newids;

#     #
#     push (@{$ways{$current_way}->{nodes}},$id);# add to way

#     $ways{$current_way}{parent}=$current_parent_way; # store the parent
#     push @{$ways{$current_parent_way}{children}},$current_way; # push the children
#     # we need to apply all relationships to the children as well. and tags if needed.
# }


# sub re_process_waynd
# {
#     my $id=shift;

#     ## now we look if we have to cut this way into new bits
#     if ($nodesways{$id}) # we have seen this node before
#     {
# 	# we need to split the way here.
# 	split_way($current_way);  # create a new way now starting at this point.       
#     }

#     # do we have to add the connection
#     push (@{$ways{$current_way}->{nodes}},$id);# add to way

#     # store the current way in the array, first one is 
#     push @{$nodesways{$id}},$current_way;
    
# }

my %waystring;


sub post_process_way
{
    my $rel  =shift;
    my $wayid =shift || carp "No way";


    if ($ways{$wayid}->{relationship})
    {
	die "way $wayid already in rel";
    }
    else
    {
	$ways{$wayid}->{relationship}=$rel;
    }
}



##### we look for two in a row.. cannot have that
my %seenfilter;
sub checkpair
{
    my $first=shift;
    my $second=shift;

    if ($first > $second)
    {
	my $t=$second;
	$second=$first;
	$first=$t;
    }
    if ($seenfilter{"${first}|${second}"}++)
    {
	# we have seen pair in reverse, bail
	#	return;
	return 0;
    }
    return 1;
}
sub checkfordups
{
    my @way=@_;
    my $last;
    my $fail=0;
    my $count=0;
    my $size=$#way + 1;

    ### now check 
    foreach my $nd (@way)
    {
	if ($last)
	{
	    if (!checkpair($nd,$last))
	    {
		# we have seen pair in reverse, bail
		#	return;
		$fail=1;
	    }		
	}
	$last=$nd;	
	$count++;
    }
    return $fail;
}

#mapping of old ways onto new
my %waymapping;

=head2
    finish_way (way_id, [@runlist])

    this is called when we have a finished set of nodes in a run (contigious) along a way
    that all have the same set of attributes, they dont need any more cutting.
    
    returns the newid, so we can append the trailing bits

=cut


sub finish_way
{
    my $wayid=shift;
    my $runlist=shift;
    my $tag =shift;
    #remove duplicates from the ways 
    my @newlist = @{$runlist};

    my $runstring= join (",",sort {$a <=> $b} @newlist);
#    print "Last Run was connected to " . join (",",@last) . "\n";
    # run string
    if ( $#newlist == 0)
    {
#	warn "only 1 object";
	return;
    }

    if ($waystring{$runstring})
    {
	# we have done this one.
	warn "Duplicate (" . $runstring . ")\n" if $debug;
	push @{$waymapping{$wayid}},$waystring{$runstring}; # push the id as a replacement for the old string
    }
    else
    {
	$newids--; # allocate a new id.
	push @{$waymapping{$wayid}},$newids; # map the old id onto the new
	$waystring{$runstring}=$newids; # give this new way an id
	warn "Run Finished (" . $runstring . ")\n" if $debug;

	# now put the nodes on the new way....
	push @{$ways{$newids}->{nodes}},@newlist;
    }

    return $newids;
}

# post process the way
sub post_process_way_end
{
    my $rel  =shift;
    my $wayid=shift;
    warn "looking at way $wayid\n" if $debug;
    my @last;
    my @run; # a run of nodes in the same context
    my $tag="";

    my $segment=0;

    my $lastnode=0;

    foreach my $nd (@{$ways{$wayid}->{nodes}})
    {
	my @others = ();

	if (!$nd)
	{
	    warn "no node";
	}
	else
	{
	    @others = @{$nodesways{$nd}}; # get a list of ways connecting to the node
	    push @run,$nd;
	}

	if (!@last) # we are at the first in the list
	{
	    @last=@others; # the first one
	    $tag="first";
	}


	if (@last != @others) # skip over the first one
	{

#### EMIT THE LAST RUN
##TODO ----------
	    finish_way ($wayid,\@run,$tag); # finish the run list
	    $segment++;
	    $tag = "segment $segment";
#######################################
	    ### new run starting
	    warn "Last Run:connected to " . join (",",@last) . "\n" if $debug;
	    warn "Starting new run\n" if $debug;
	    # get the last from the old run
	    my $last = pop @run; #
	    @run=();
	    push @run,$last;
## reporting
	    if ($#others > 0)
	    {
		# many others
		warn "Run : connected to " . join (",",@others) . "\n" if $debug;
	    }
	    else
	    {
		# on other
		if ($others[0] == $wayid)
		{
		    warn "Just this way :$wayid\n" if $debug;
#		    push @run,$nd;
		}
		else
		{
		    die "wtf";
		}
		#warn "$nd is not connected?" . join (",",@others) ;
	    }
	}
	else
	{
#	    same as before, add to the run
	}

	###
#	print "NODE $nd is connected to " . join (",",@others) . "\n";	
	@last=@others;
    }


    #########################
    warn "Finish up run\n" if $debug;
    finish_way ($wayid,\@run, "last");
   
    warn "way done $wayid\n" if $debug;

#####################################################################
    # emit the last element in the loop
    ############################################################
    
}

sub process_waynd
{
#    $debug=1;
    my $id=shift;
    if ($replace{$id})
    {
	my $new=$replace{$id};
	$id=$new;	
    }

    # dont add duplicates in array
    # look if the nodesways(what ways are in this node)
    if (!(grep {/$current_way/} @{$nodesways{$id}}))
    {
	# what whays is this node in
	push @{$nodesways{$id}},$current_way; # store the way in the node
    }    

    my $count = $#{$ways{$current_way}->{nodes}};

    if ($count < 1)
    {
	warn "Got count $count";
    }

    # done add duplicates to end of way
    if ($ways{$current_way}) # look up the current way
    {

	my $lastinway=$skip || $ways{$current_way}->{nodes}[-1] || 0;

	if ($lastinway ne $id) # not the last in the way
	{
	    my $other=0;

	    if (checkpair($lastinway, $id)) # remove all duplicate ways
	    {
		# the first is missing
		if ($count <= 0) 
		{
		    if ($lastinway)
		    {
			warn "adding first $lastinway";
			push (@{$ways{$current_way}->{nodes}},$lastinway);# store the first
		    }
		}

		warn "adding pair $lastinway, $id\n" if $debug;
		my $lastitem = $ways{$current_way}->{nodes}[-1];
		carp "inconsistent data $lastitem and count $count " unless $ways{$current_way}->{nodes}[-1]==$lastinway;
		push (@{$ways{$current_way}->{nodes}},$id);# store the node     
		$skip=0;
	    }
	    else
	    {
		warn "going to skip $id\n" if $debug;
		# remove this way.
		$skip=$id; # save this for usage.
		return; # break 
	    }
	}
	else
	{
	    warn "$lastinway eq $id, skipping" if $debug;
	}
    }
    else
    {
	#start a new way
	#push (@{$ways{$current_way}->{nodes}},$id);# store the node     
	$skip=$id; # add this id to the skip list, so we can add it.
#	warn "null :$current_way " . Dumper($ways{$current_way});
    }

#    $debug=0;
}

#my %checksum;
sub node
{
    my $id=shift;
    my $lat=shift;
    my $lon=shift;
    my $slat=sprintf("%0.${tolerance}f",$lat);
    my $slon=sprintf("%0.${tolerance}f",$lon);

    if ($nodes{$slat}{$slon})
    {
	my $old=$nodes{$slat}{$slon};	
	$replace{$id}=$old;
	return $old;
    }
    else
    {
	$nodes{$slat}{$slon}=$id;
	$nodeids{$id}=[$lat,$lon]; # store the nodes values

	return $id;
    }
}

my $QUOTE="[\\'\\\"]";
sub consumeattrs
{
    if (s/timestamp=${QUOTE}[\d\-T:Z]+${QUOTE}//)
    {
	#remove timestable
    }
    
    if (s/changeset=${QUOTE}\d+${QUOTE}\s*//)
    {
	#remove changeset
    }
    if (s/uid=${QUOTE}\d+${QUOTE}\s?//)
    {}

    if (s/user=${QUOTE}[\w\s]+${QUOTE}\s*//)
    {
    }
    
    if (s/visible=${QUOTE}(true|false)${QUOTE}\s*//)
    {
	
    }
    
    if (s/action=${QUOTE}modify${QUOTE}\s*//)
    {
#	    warn "check $_";
    }
    
    if (/action=${QUOTE}delete${QUOTE}/)
    {
	#next; # skip this
	return 0;
    }

    if (s/version=${QUOTE}\d+${QUOTE}\s*//)
    {
	#remove version
    }

    return 1;

#    warn "done $_";
}

sub parse
{
    my $file=shift;
    open IN, $file or die;
    my $coordpattern = "-?[\\d\\.\\-Ee]+";
    my $QUOTE="[\\'\\\"]";

    my $lat=0;
    my $lon=0;
    my $current_rel=0;
    while (<IN>)
    {
	if (/<\?xml version=${QUOTE}1.0${QUOTE}/)  #encoding=${QUOTE}UTF-8${QUOTE}\?
	{
	}
	elsif (/<osm version=${QUOTE}0.\d${QUOTE} /) #generator=${QUOTE}[\w\s]+${QUOTE}>
	{
    }
    elsif (/<node/)
    {
	next unless consumeattrs;
	if (s/lon=${QUOTE}($coordpattern)${QUOTE} //)
	{
	    $lon=$1;
#	    warn "LON $1";
	}
	else
	{
	    die "no lon $coordpattern $_";
	}
	
	if (s/lat=${QUOTE}($coordpattern)${QUOTE} //)
	{
	    $lat=$1;
#	    warn "LAT $1";
	}
	else
	{
	    die "no lat $_";
	}
	
	if (/<node id=${QUOTE}(-?\d+)${QUOTE}\s*\/?>/)
	{
	    node($1,$lat,$lon);
	}
	else
	{	    
	    die "Missing 2 $_";
	}
	
    }
    elsif (/<\/node/)
    {
	#end of node
    }
    elsif (/\s*<way/){


#	consumeattrs;
	next unless consumeattrs;

	if (/\s*<way id=${QUOTE}(\-?\d+)${QUOTE}\s*>/)
	{
	    begin_way $1;	    
	}
	else
	{
	    die "missing way $_";
	}

    }
    elsif(/<nd ref=${QUOTE}(-?\d+)${QUOTE}\s*\/>/)
    {
	process_waynd($1);
    }
    elsif (/<\/way>/){
	# end of way
	end_way;
    }
#    <way id=${QUOTE}-572620${QUOTE} action=${QUOTE}modify${QUOTE} timestamp=${QUOTE}2010-12-05T01:31:40Z${QUOTE} visible=${QUOTE}true${QUOTE}>
    elsif (/<nd ref=${QUOTE}(-_\d)${QUOTE} \/>/){}
	elsif (/<relation/){
	    
#	consumeattrs;
	    next unless consumeattrs;
	    
	if (/<relation id=${QUOTE}(\-?\d+)${QUOTE}\s*/)
	{
	    $current_rel=$1;
	}
	else
	{
	    die "Bad Relation $_";
	}

	    # all on one line?
	    while (s/<member type=${QUOTE}way${QUOTE} ref=${QUOTE}(-?\d+)${QUOTE} role=${QUOTE}outer${QUOTE}\s?\/>//){
		
		# now we want to post process this way
		# cut the way on all the intersections with all other relations
		# remove other ways that are duplicate, match it 100%
#		warn "member $_";
		post_process_way($current_rel,$1); 
	    }

    }
	
	elsif (/<\/relation>/){
	    $current_rel=0;
	}
	elsif (/<member type=${QUOTE}way${QUOTE} ref=${QUOTE}(-?\d+)${QUOTE} role=${QUOTE}outer${QUOTE}\s?\/>/){

	# now we want to post process this way
	# cut the way on all the intersections with all other relations
	# remove other ways that are duplicate, match it 100%
#	warn "member $_";
	post_process_way($current_rel,$1); 
    }
    elsif (/<member type=${QUOTE}node${QUOTE} ref=${QUOTE}(-?\d+)${QUOTE} role=${QUOTE}admin_centre${QUOTE}\s?\/>/){}
    elsif (/<tag k=${QUOTE}(.+)${QUOTE} v=${QUOTE}(.+)${QUOTE}\s*\/>/)
    {
	while (s/<tag k=${QUOTE}([^\/\${QUOTE}]+)${QUOTE} v=${QUOTE}([^\/\${QUOTE}]+)${QUOTE}\s*\/>//)
	{
#	    warn "$2";
	    if ($current_rel)
	    {
		$tags{$current_rel}{$1}=$2;
	    }
	    if ($current_way)
	    {
		$tags{$current_way}{$1}=$2;
	    }
	}
    }
    elsif (/<\/osm>/)
    {
    }
    elsif (/^\s+$/)
    {
    }
    else
    {
	die "Missing anything $_";
    }
}
close IN;
}

my %rels; # the relationships

sub post_process_ways
{
    foreach my $wayid (sort keys %ways)
    {
	my $rel =$ways{$wayid}->{relationship};
	post_process_way_end $rel, $wayid;
    }
}


foreach my $file (@ARGV)
{
    parse $file;
}

post_process_ways;

foreach my $wayid (sort keys %ways)
{   
    my $rel =$ways{$wayid}->{relationship};
    if ($rel)
    {
	# these relationships contains these ways
	push @{$rels{$rel}},$wayid;###
    }
    else
    {
#	warn "no rel found, must be new";
#	warn Dumper($ways{$wayid});
    }
}	
#warn Dumper(\%waymapping); # dump out the ways 
# now we can emit the relationships with the new ways instead of the old ones.

my %seen; # what have we emitted
#####################################################
### now output the doc 
print "<osm version='0.6'>\n";

foreach my $rel (keys %{rels})
{
#    warn "emit $rel\n";
#    warn Dumper($tags{$rel});
 #   warn Dumper($rels{$rel});
    my @ways;
    foreach my $oldway ( @{$rels{$rel}})
    {
	warn "found old way $oldway" if $debug;

	foreach my $newway (@{$waymapping{$oldway}}	)
	{
	    # add the new ways
	    push @ways,$newway;

	    if (!$seen{$newway}++) 
	    {
		warn "found new way $newway" if $debug;
#		if (!$fail)
		{

		foreach my $nd (@{$ways{$newway}->{nodes}})
		{
		    # have we emitted the node yet?
		    print "$nd in $newway\n" if $debug;
		    
		    if (!$seen{$nd}++) 
		    {		    
#			emitnode($nd, @{$nodeids{$nd}});
			my ($lat,$lon)=@{$nodeids{$nd}};
			print "<node id=\'$nd\' lat='$lat' lon='$lon'>\n";
			print "<tag k='_ID' v='$nd' />\n";
			print "</node>\n";
		    }
		    
		}
		# emit new way------------------------ 
		print "<way id='$newway'>\n";
		foreach my $nd (@{$ways{$newway}->{nodes}})
		{
		    print "<nd ref='$nd'/>\t";
		}
		print "<tag k='is_in:country' v='Colombia'/>\n";
		print "<tag k='_ID' v='$newway' />\n";

		print "</way>\n";
		}

	    }
	    else
	    {
		#reusing the way
	    }
	}## after all new ways
	

    }# after old ways


    # relationships
    if (!$seen{$rel}++) 
    {
	## emit the ways 
	print "<relation id='$rel'>\n";
	foreach my $w (@ways)
	{
	    # emit the ways
	    print "<member type='way' ref='$w' role='outer'/>\n";
	}	
	# keys
	foreach my $k (sort keys %{$tags{$rel}})
	{
	    my $v=$tags{$rel}{$k};
	    print "<tag k='$k' v='$v' />\n";
	}

	print "<tag k='_ID' v='$rel' />\n";
	print "</relation>\n";
    }
    # now emit the relationship
    #warn Dumper($tags{$rel});

}# end of relationship
print "</osm>\n";
