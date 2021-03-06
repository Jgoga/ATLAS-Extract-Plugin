#!/usr/bin/perl
use JSON::PP;
use Data::Dumper;
use List::MoreUtils qw(uniq);

my $gridUnits = 1400000;
my $numGridsX = 11;
my $numGridsY = 11;
my $worldUnits = $gridUnits * $numGridsX;

open( my $fh, "<", "server/ShooterGame/ServerGrid.json" ) or die("cant open ServerGrid.json");
my $serverConfig = decode_json(
    do { local $/; <$fh> }
);
close $fh;

open( my $fh, "<", "mapResources.json" ) or die("cant open mapResources.json");
my $mapResources = decode_json(
    do { local $/; <$fh> }
);
close $fh;

my %rawData, @stones, @bosses;
for (my $x = 0; $x < $numGridsX; $x++) {
    for (my $y = 0; $y < $numGridsY; $y++) {
        my $grid = chr( 65 + $x ) . ( 1 + $y );
        open( my $fh, "<", "./server/ShooterGame/Binaries/Win64/resources/$grid.json" ) or next;
        $rawData{$grid} = decode_json(
            do { local $/; <$fh> }
        );
        if ($rawData{$grid}{"Stones"}) {
            foreach $stone (keys %{$rawData{$grid}{"Stones"}} ) {
                push @stones, 
                { 
                    name => $stone, 
                    long => $rawData{$grid}{"Stones"}{$stone}[0], 
                    lat => $rawData{$grid}{"Stones"}{$stone}[1], 
                };
            }
        }

        if ($rawData{$grid}{"Boss"}) {
            foreach $boss (keys %{$rawData{$grid}{"Boss"}} ) {
                 foreach $position (@{$rawData{$grid}{"Boss"}{$boss}}) {
                    push @bosses, 
                    { 
                        name => $boss, 
                        long => @{$position}[0], 
                        lat => @{$position}[1], 
                    };
                 }
            }
        }

        close $fh;
    }
}

my %key_islandID;
foreach $server ( @{ $serverConfig->{'servers'} } ) {
    foreach $island ( @{ $server->{'islandInstances'} } ) {
        my $grid = chr( 65 + $server->{gridX} ) . ( 1 + $server->{gridY} );
        $island->{grid} = $grid;
        $key_islandID{ $island->{id} } = $island;
        $key_islandID{ $island->{id} }->{homeServer} = $server->{isHomeServer};

        if ($server->{OverrideShooterGameModeDefaultGameIni}->{bDontUseClaimFlags} == undef && $server->{name} !~ /Freeport/) {
            $key_islandID{ $island->{id} }->{claimable} = 1;
        } else {
            $key_islandID{ $island->{id} }->{claimable} = 0;
        }

        if ($island->{treasureMapSpawnPoints}) {
            $key_islandID{ $island->{id} }->{resources}{"Treasure Spawns"} = scalar @{ $island->{treasureMapSpawnPoints} };
        }

        # get resources
        foreach my $key (keys %{ $rawData{$grid}{"Resources"} } ) {
            my @coords = GPSToWorld(split(/:/, $key));
            if (
                inside(
                    $island->{worldX} - ($island->{islandHeight} / 2),
                    $island->{worldY} - ($island->{islandHeight} / 2),
                    $island->{worldX} + ($island->{islandHeight} / 2),
                    $island->{worldY} + ($island->{islandHeight} / 2),
                    $coords[0],
                    $coords[1],
                )
              )
            {
                foreach my $hash (keys %{$rawData{$grid}{"Resources"}{$key}}) { 
                  $key_islandID{ $island->{id} }->{resources}{$hash} =  $rawData{$grid}{"Resources"}{$key}{$hash} ;
                }
            }   
        }
        foreach my $key (keys %{ $rawData{$grid}{"Maps"} } ) {
            my @coords = GPSToWorld(split(/:/, $key));
            if (
                inside(
                    $island->{worldX} - ($island->{islandHeight} / 2),
                    $island->{worldY} - ($island->{islandHeight} / 2),
                    $island->{worldX} + ($island->{islandHeight} / 2),
                    $island->{worldY} + ($island->{islandHeight} / 2),
                    $coords[0],
                    $coords[1],
                )
              )
            {
                $key_islandID{ $island->{id} }->{maps} =  $rawData{$grid}{"Maps"}{$key} ;
            }   
        }

        foreach my $key (keys %{ $rawData{$grid}{"Meshes"} } ) {
            my @coords = GPSToWorld(split(/:/, $key));
            if (
                inside(
                    $island->{worldX} - ($island->{islandHeight} / 2),
                    $island->{worldY} - ($island->{islandHeight} / 2),
                    $island->{worldX} + ($island->{islandHeight} / 2),
                    $island->{worldY} + ($island->{islandHeight} / 2),
                    $coords[0],
                    $coords[1],
                )
              )
            {
                $key_islandID{ $island->{id} }->{meshes} =  $rawData{$grid}{"Meshes"}{$key} ;
            }   
        }

        foreach my $disco ( @{ $server->{'discoZones'} } ) {
            if (
                $disco->{bIsManuallyPlaced} == JSON::PP::false &&
                inside(
                    $island->{worldX} - ($island->{islandHeight} / 2),
                    $island->{worldY} - ($island->{islandHeight} / 2),
                    $island->{worldX} + ($island->{islandHeight} / 2),
                    $island->{worldY} + ($island->{islandHeight} / 2),
                    $disco->{worldX},
                    $disco->{worldY}
                )
              )
            {
                my @coords = worldToGPS($disco->{worldX}, $disco->{worldY});
                push @{ $key_islandID{ $island->{id} }->{discoveries} }, 
                { 
                    name => $disco->{name}, 
                    long => $coords[0], 
                    lat => $coords[1], 
                };
            }

            if ($rawData{$grid}{"Discoveries"}{$disco->{ManualVolumeName}}) {
                my @gps = @{$rawData{$grid}{"Discoveries"}{$disco->{ManualVolumeName}}};
                my @coords = GPSToWorld(@gps);
                if (
                    inside(
                        $island->{worldX} - ($island->{islandHeight} / 1.8),
                        $island->{worldY} - ($island->{islandWidth} / 1.8),
                        $island->{worldX} + ($island->{islandHeight} / 1.8),
                        $island->{worldY} + ($island->{islandWidth} / 1.8),
                        $coords[0],
                        $coords[1],
                    )
                )
                {
                    push @{ $key_islandID{ $island->{id} }->{discoveries} }, 
                    { 
                        name => $disco->{name}, 
                        long => $rawData{$grid}{"Discoveries"}{$disco->{ManualVolumeName}}[0], 
                        lat => $rawData{$grid}{"Discoveries"}{$disco->{ManualVolumeName}}[1], 
                    };
                }
            }
        }
    }

    foreach my $sublevel ( @{ $server->{'sublevels'} } ) {
        push(
            @{ $key_islandID{ $sublevel->{id} }->{sublevels} },
            $sublevel->{name}
        );
        if ( $mapResources->{ $sublevel->{name} } ) {
            if ( $mapResources->{ $sublevel->{name} }->{overrides} ) {
                foreach my $resource (
                    @{ $mapResources->{ $sublevel->{name} }->{overrides} } )
                {
                    push @{ $key_islandID{ $sublevel->{id} }->{animals} },
                      $resource;
                }
            }            
        }
       
        @{ $key_islandID{ $sublevel->{id} }->{animals} } =
          uniq  @{ $key_islandID{ $sublevel->{id} }->{animals} };
    }
}

my %key_grid, %island_grid;
foreach my $island (keys %key_islandID)
{
    foreach my $resource (  keys %{ $key_islandID{ $island }->{resources} }  )
    {
        push(@{$key_grid{ $key_islandID{$island}->{grid} }->{resources}}, $resource);
        @{ $key_grid{ $key_islandID{$island}->{grid} }->{resources} } = uniq sort @{$key_grid{$key_islandID{$island}->{grid}}->{resources} };

        push(@{$island_grid{ $key_islandID{$island}->{name} }->{resources}}, $resource);
        @{ $island_grid{ $key_islandID{$island}->{name}}->{resources} } = uniq sort @{$island_grid{$key_islandID{$island}->{name}}->{resources} };
        
    }
    foreach my $resource ( @{$key_islandID{ $island }->{animals}} )
    {
        push(
            @{$key_grid{$key_islandID{$island}->{grid}}->{animals}}, 
            $resource);
        @{ $key_grid{$key_islandID{$island}->{grid}}->{animals} } =
        uniq sort @{ $key_grid{$key_islandID{$island}->{grid}}->{animals} };
    }
    $key_grid{$key_islandID{$island}->{grid}}->{claimable} += $key_islandID{ $island }->{claimable};
}

jsonOut(\%key_islandID, "islands.json");
jsonOut(\%key_grid, "gridList.json");
jsonOut(\%island_grid, "islandList.json");
jsonOut($serverConfig->{'shipPaths'}, "shipPaths.json");
jsonOut(\@stones, "stones.json");
jsonOut(\@bosses, "bosses.json");

sub jsonOut {
    local ( $data, $filename ) = @_;
    my $json = JSON::PP->new->ascii->pretty->allow_nonref;
    open( my $fh, ">", $filename ) or die "cannot write " . $filename;
    print $fh $json->encode( $data );
    close($fh);
}

sub inside {
    local ( $x1, $y1, $x2, $y2, $x, $y ) = @_;
    if (   $x > $x1
        && $x < $x2
        && $y > $y1
        && $y < $y2 )
    {
        return 1;
    }
    return 0;
}

sub worldToGPS {
  my ($x, $y) = @_;
  my $long = (($x / $worldUnits) * 200) - 100;
  my $lat = 100 - (($y / $worldUnits) * 200);
  return ($long,$lat);
}

sub GPSToWorld {
  my ($x, $y) = @_;
  my $long = ( ( $x + 100 ) / 200 ) * $worldUnits;
  my $lat =  ( (-$y + 100 ) / 200  ) * $worldUnits;
  return ($long,$lat);
}