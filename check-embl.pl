#!/usr/bin/perl -w

use strict;
use warnings;
use Carp;

use Bio::SeqIO;
use Bio::Chado::Schema;


while (defined (my $file = shift)) {

  my $io = Bio::SeqIO->new(-file => $file, -format => "embl" );
  my $seq_obj = $io->next_seq;
  my $anno_collection = $seq_obj->annotation;

  sub _dump_feature
    {
      my $feature = shift;

      for my $tag ($feature->get_all_tags) {
        print "  tag: ", $tag, "\n";
        for my $value ($feature->get_tag_values($tag)) {
          print "    value: ", $value, "\n";
        }
      }
    }

  my %seen_ids = ();

  for my $feature ($seq_obj->get_SeqFeatures) {
    my $type = $feature->primary_tag();

    next unless $type =~ /UTR/;

    my @systematic_ids = $feature->get_tag_values("systematic_id");

    if (@systematic_ids != 1) {
      my $systematic_id_count = scalar(@systematic_ids);
      warn "\nexpected 1 systematic_id, got $systematic_id_count, for:";
      _dump_feature($feature);
      exit(1);
    }

    my $systematic_id = $systematic_ids[0];

    if (exists $seen_ids{$type}->{$systematic_id}) {
      warn "duplicated id for $type: $systematic_id\n";
    }

    $seen_ids{$type}->{$systematic_id} = 1;

    #  print "$type: $systematic_id\n";
  }
}
