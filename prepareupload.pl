use strict;
use warnings;
use Data::Dumper;
use Carp;

=head1
    1. empty ways
    2. double points in way
    3. 
=cut

my $tolerance=20;
my %nodes;
my %replace; # replace these ids with these
my %nodeids; # lookup the latlon of the nodes
my %nodesways; # what ways are these nodes used in
my %tags; # store the tags

my $newids = -3000000; # we give new objects ids starting here
my $current_way;
my $debug=1;
my %ways;
my %waystring;
# just store the last node seen an used that.
my $last_node_seen=0;
my %rels; # the relationships
#mapping of old ways onto new
my %waymapping;

##### we look for two in a row.. cannot have that
my %seenfilter;
my $QUOTE="[\\'\\\"]";
my %seen; # what have we emitted

=head2
new algorithm for removing duplicate way.

1. each segment is stored attached to the node. 
node has a list of in and out arcs each contain the from and two nodes
each arc contains the way(s) and relations(s) it belongs to.
if we find a duplicate segment, we can replace it immediatly.
=cut


my %node_arcs;
# {NODE ID} -> {in_arcs} = list
# {NODE ID} -> {out_arcs} = list

sub undup
{
    my $id=shift;
    if ($replace{$id})
    {
	my $new=$replace{$id};
	warn "adding replacing $id with $new in way $current_way\n" if $debug;
	$id=$new;	
    }
    return $id;

}

my %ways_to_split;

sub add_arc_to_node
{
    my $from_nodeid=undup(shift);
    my $to_nodeid=undup(shift);
    my $in_way=shift;
    my $arc = [$from_nodeid,$to_nodeid,$in_way,0]; # the opposite way is null
    
    foreach my $n ($from_nodeid,$to_nodeid)
    {
	if ($node_arcs{$n})
	{
	    foreach my $i (@{$node_arcs{$n}})
	    {
		if ($from_nodeid == $i->[0]) # from node
		{
		    if ($to_nodeid == $i->[1]) # to node
		    {
			# match
#		    warn "duplicate" if $debug;
			warn "duplicate tuplie $from_nodeid -> $to_nodeid : in way" . $in_way . "\n" ;

		    }
		}
		if ($from_nodeid == $i->[1]) # from node
		{
		    if ($to_nodeid == $i->[0]) # to node
		    {
			# match in the other direction
			$i->[3]=$in_way; # store the opposite direction
#			warn "found opposite way $to_nodeid -> $from_nodeid : new way" . $in_way . " old way : ". $i->[2];
			$ways_to_split{$i->[2]}=$i->[3];
			return;
		    }
		}
	    }       
	}
	#add a node
    }
    push @{$node_arcs{$from_nodeid}},$arc;

}


sub make_new_way
{
    my $wayid =shift; # old way
    my @newlist =@_;  # all the new points to add 
    if (@newlist)
    {
	$newids--; # allocate a new id for the way
	push @{$ways{$newids}->{nodes}},@newlist;
	push @{$waymapping{$wayid}},$newids; # map the old id onto the new
	warn "new way $newids contains" . join (",",@{$ways{$newids}->{nodes}}) . "\n";
    }
    else
    {
	warn "Empty list $wayid called";
    }

}

sub remove_duplicate_ways
{
    # after we have looked at all the ways, we can remove the duplicates
#    warn Dumper(\%ways_to_split);
    # the new side is on the left, the old side on the right.
    # we want to remove all the right side from the relations, add the left side to them
    # we do that by creating new ways from them, all the new ways will be references from the old for the purposes of making the relations
    # but first we need to split the side into the smallest common denominators
    # we look at a way, look at all the parts to it, see if the duplicate flag is set, and then split the way there.
    foreach my $wayid (sort keys %ways)
    {
	warn "looking at $wayid for splitting \n";	

	my $rel =$ways{$wayid}->{relationship};
	my @newpoints=();
	#

	if ($ways{$wayid})
	{
	    my @oldnodes= @{$ways{$wayid}->{nodes}};
	    warn "oldway $wayid contains" . join (",",@oldnodes) . "\n";	
	    
	    foreach my $nd (@oldnodes)
	    {
		push @newpoints,$nd;
		my $otherway=0;
			       
		warn "$nd has arcs ". Dumper(@{$node_arcs{$nd}}) . "\n";
		foreach my $arc (@{$node_arcs{$nd}})
		{		
		    if ($arc->[2] == $wayid)
		    {
			if ($arc->[3]) # should be split
			{
			    # is the way different?
			    
			    if ($otherway==0) #for the first node, we just add that.
			    {
				$otherway=$arc->[3];
			    }
			    if ($arc->[3] != $otherway) # second round
			    {
				#we split here
				warn "going to make new way $wayid contains" . join (",",@newpoints) . "\n";	
				
				make_new_way($wayid,@newpoints);
				@newpoints=();
				$otherway=$arc->[3];			    
			    }
			} # is there another wayy, a reverse way
		    }# only look at the arcs from this way in the node
		}# for all arcs
	    }
	}
	warn "leftovers for new $wayid contains" . join (",",@newpoints) . "\n";	

	if (@newpoints)
	{
	    make_new_way($wayid,@newpoints);	
	}

    }    
    # then we add those parts to the new relations.

    # add the points to a new list 

}

sub begin_way
{
    my $id=shift;
    $current_way = $id;
    warn "setting current way:$current_way" if $debug;
    $last_node_seen=0;
}

sub end_way
{
    warn "closing current way:$current_way" if $debug;
    warn "Way $current_way contains" . join (",",@{$ways{$current_way}->{nodes}}) . "\n" if $debug;

    $current_way=undef;
    $last_node_seen=0;
}

sub checksum
{
    my $lat=shift;
    my $lon=shift;
    my $checksum =(($lat + 180) *100000000000) + (($lon + 180) *1000000);
    return int($checksum);
}

sub post_process_way
{
    my $rel  =shift;
    my $wayid =shift || die carp "No way";
    if ($ways{$wayid}->{relationship})
    {
	die "way $wayid already in rel";
    }
    else
    {
	$ways{$wayid}->{relationship}=$rel;
    }
}

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
	warn "seen pair: first:${first} second:${second} skipping" if $debug;
	# we have seen pair in reverse, bail
	#	return;
	return 0;
    }
    return 1;
}

=head2
    finish_way (way_id, [@runlist])
    this is called when we have a finished set of nodes in a run (contigious) along a way
    that all have the same set of attributes, they dont need any more cutting.    
    returns the newid, so we can append the trailing bits
=cut

sub finish_way
{

}
sub finish_way_old
{

    my $wayid=shift;
    my $runlist=shift;
    my $tag =shift;
    #remove duplicates from the ways 
    my @newlist = @{$runlist};
    $last_node_seen=0; #reset
    my $runstring= join (",",sort {$a <=> $b} @newlist);
    warn "Run for $wayid with tag $tag contains " . join (",",@newlist) . "\n" if $debug;
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
	warn "Run in way $wayid Finished (" . $runstring . ")\n" if $debug;
	# now put the nodes on the new way....
	push @{$ways{$newids}->{nodes}},@newlist;
    }
    return $newids;
}

# post process the way
sub post_process_way_end
{
}

sub post_process_way_end_old
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
	    warn "node $nd is connected to ways: " . join (",",@others) . "\n" if $debug;
	    warn "Last Run:connected to " . join (",",@last) . "\n" if $debug;
	    warn "Starting new run\n" if $debug;
	    # get the last from the old run
	    my $last = pop @run; #
	    @run=();
	    warn "adding into way:$wayid node:$last\n" if $debug;
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
	    warn "duplicate in way:$wayid  node:$nd\n" if $debug;
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

sub way_in_node
{
    my $way=shift;
    my $id=shift;
    my $isok=1;
    foreach my $chk (@{$nodesways{$id}})
    {
	if ($chk eq $way)
	{
	    return 1;
	}
    }
    return 0;
}

sub process_waynd
{
    my $id=shift;
    warn "process_waynd $id in way $current_way\n" if $debug;
    if ($replace{$id})
    {
	my $new=$replace{$id};
	warn "adding replacing $id with $new in way $current_way\n" if $debug;
	$id=$new;	
    }
    # dont add duplicates in array
    # look if the nodesways(what ways are in this node)
    if (!way_in_node($current_way,$id))
    {
	# what whays is this node in
	warn "adding node:$id to way:$current_way\n" if $debug;
	push @{$nodesways{$id}},$current_way; # store the way in the node
    }    
    my $count = $#{$ways{$current_way}->{nodes}};
    if ($count < 0)
    {
	warn "Got count $count of nodes in $current_way\n" if $debug;
    }
    # done add duplicates to end of way
    if ($ways{$current_way}) # look up the current way
    {
#	my $lastinway=$last_node_seen;
	#my $lastinway=$ways{$current_way}->{nodes}[-1] || 0;
	# the first is missing
	my $lastitem = $ways{$current_way}->{nodes}[-1]; # the last item in the way
	
	if(!$lastitem)
	{
	    warn "lastitem is null for $current_way" if $debug;
#	    warn Dumper($ways{$current_way});
	    push (@{$ways{$current_way}->{nodes}},$id);# store the node     
	}
	else
	{
	    warn "last in way node :$lastitem in way:$current_way\n" if $debug;
	    if ($lastitem ne $id) # not the last in the way
	    {
		my $other=0;
		
	    
		# build up the new structure
		add_arc_to_node($lastitem, $id, $current_way);
		
		#  if (checkpair($lastinway, $id)) # remove all duplicate ways
		{
#		    warn "in way $current_way adding pair lastinway :$lastinway | lastitem:$lastitem, node:$id\n" if $debug;
		    
		    push (@{$ways{$current_way}->{nodes}},$id);# store the node     
		    
		    
		    # only store the last node seen if it is not a duplicate
		    $last_node_seen=$id;
		    
		}# if check pair

	    }
	} # 
    }
    else
    {
	warn "start new way: $current_way" if $debug;
	#start a new way
	push (@{$ways{$current_way}->{nodes}},$id);# store the node     
#	warn "null :$current_way " . Dumper($ways{$current_way});
    }

#    $debug=0;
}

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
	elsif (/<osm version=${QUOTE}0.\d${QUOTE}/) #generator=${QUOTE}[\w\s]+${QUOTE}>
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

=head2
    duplicate way algorithm

    1. each node has a pointer to a set of arc, the next node.
    2. if the next node points back to this node, it is duplicate, we remove it.
=cut

sub post_process_ways
{
    foreach my $wayid (sort keys %ways)
    {
	my $rel =$ways{$wayid}->{relationship};
	#post_process_way_end $rel, $wayid; # for each way, lets process it.
	push @{$waymapping{$wayid}},$wayid; # map onto self for now
    }
}


##################### MAIN ROUTINE TO CLEAN

foreach my $file (@ARGV)
{
    parse $file;
}
#post_process_ways;
remove_duplicate_ways;
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
=head2
    here we map all old ways onto new ways.
    the old ways are not used, only the new ones, recreated from the old
    the waymapping hash manages that
=cut
	foreach my $newway (@{$waymapping{$oldway}}	)
	{
	    # add the new ways
	    push @ways,$newway;
	    if (!$seen{$newway}++) 
	    {
		warn "found new way $newway from old way $oldway" if $debug;
#		if (!$fail)
		{
		    foreach my $nd (@{$ways{$newway}->{nodes}})
		    {
			# have we emitted the node yet?
			warn "$nd in $newway\n" if $debug;
			
			if (!$seen{$nd}++) 
			{		    
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
