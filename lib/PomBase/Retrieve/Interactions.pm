package PomBase::Retrieve::Interactions;

=head1 NAME

PomBase::Retrieve::Interactions - Code for retrieving interactions in
                                  BioGRID format

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::Interactions

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

use Getopt::Long qw(GetOptionsFromArray :config pass_through);

use Iterator::Simple qw(iterator);

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';

has since_date => (is => 'rw');

sub BUILDARGS
{
  my $class = shift;
  my %args = @_;

  my $since_date = undef;

  my @opt_config = ("since-date=s" => \$since_date);

  if (!GetOptionsFromArray($args{options}, @opt_config)) {
    croak "option parsing failed";
  }

  if (defined $since_date) {
    $args{since_date} = $since_date;
  }

  return \%args;
}


method _organism_taxonid($organism) {
  state $cache = {};

  my $organism_id = $organism->organism_id();

  if (!exists $cache->{$organism_id}) {
    my $taxonid_term = $self->get_cvterm('PomBase organism property types',
                                         'taxon_id');

    my $prop_rs = $organism->organismprops()->search({ type_id => $taxonid_term->cvterm_id() });
    $cache->{$organism_id} = $prop_rs->first()->value();
  }

  return $cache->{$organism_id};
}

method _read_rel_props($rel_rs) {
  my %props = ();

  my $prop_rs = $self->chado()->resultset('Sequence::FeatureRelationshipprop')
          ->search(
            {
              feature_relationship_id => {
                -in => $rel_rs->get_column('feature_relationship_id')->as_query(),
              }
            }, { prefetch => [ 'type' ] });

  while (defined (my $prop = $prop_rs->next())) {
    $props{$prop->feature_relationship_id()}{$prop->type()->name()} = $prop->value();
  }

  return %props;
}

method _read_pubs($rel_rs) {
  my %pubs = ();

  my $pubs_rs = $self->chado()->resultset('Sequence::FeatureRelationshipPub')
          ->search(
            {
              feature_relationship_id => {
                -in => $rel_rs->get_column('feature_relationship_id')->as_query(),
              }
            },
            { prefetch => [ 'pub' ] });

  while (defined (my $pub_rel = $pubs_rs->next())) {
    $pubs{$pub_rel->feature_relationship_id()} = $pub_rel->pub()->uniquename();
  }

  return %pubs;
}

method retrieve() {
  my $chado = $self->chado();

  my $org_taxonid = $self->organism_taxonid();
  my $org = $self->organism();

  my $interacts_genetically_id =
    $self->get_cvterm('PomBase interaction types', 'interacts_genetically')->cvterm_id();
  my $interacts_physically_id =
    $self->get_cvterm('PomBase interaction types', 'interacts_physically')->cvterm_id();

  my $rel_rs = $chado->resultset('Sequence::FeatureRelationship')
                     ->search(
                       {
                         -and => [
                           -or => [ 'subject.organism_id' => $org->organism_id(),
                                    'object.organism_id' => $org->organism_id()
                                  ],
                           -or => [ 'me.type_id' => $interacts_genetically_id,
                                    'me.type_id' => $interacts_physically_id,
                                  ],
                         ],

                       },
                       {
                         prefetch => { subject => [ 'type', 'organism' ],
                                       object => [ 'type', 'organism' ] },
                       });

  if (defined $self->since_date()) {
    my $since_date = $self->since_date();
    my $where_sql = <<"SQL";
me.feature_relationship_id IN
 (SELECT feature_relationship_id FROM feature_relationshipprop p
    JOIN cvterm ptype ON p.type_id = ptype.cvterm_id
   WHERE ptype.name = 'date' AND
      (CASE WHEN ptype.name = 'date' AND p.value IS NOT NULL
            THEN value::date ELSE NULL END) >= date '$since_date')
SQL

    $rel_rs = $rel_rs->search({},
                              {
                                where => \$where_sql,
                              });
  }

  my %props = $self->_read_rel_props($rel_rs);
  my %pubs = $self->_read_pubs($rel_rs);

  my $db_name = $self->config()->{database_name};

  my $it = do {
    iterator {
    ROW: {
        my $row = $rel_rs->next();

        if (defined $row) {
          my $is_inferred = $props{$row->feature_relationship_id()}{is_inferred};

          goto ROW if $is_inferred eq 'yes';

          my $source_database = $props{$row->feature_relationship_id()}{source_database};
          if ($source_database ne $db_name) {
            goto ROW;
          }

          my $gene_a_uniquename = $row->subject()->uniquename();
          my $org_a_taxonid = $self->_organism_taxonid($row->subject()->organism());
          my $gene_b_uniquename = $row->object()->uniquename();
          my $org_b_taxonid = $self->_organism_taxonid($row->object()->organism());
          my $evidence_code = $props{$row->feature_relationship_id()}{evidence};
          my $pubmedid = $pubs{$row->feature_relationship_id()};
          my $date = $props{$row->feature_relationship_id()}{date};

          return [$gene_a_uniquename, $gene_b_uniquename,
                  $org_a_taxonid, $org_b_taxonid,
                  $evidence_code, $pubmedid, '',
                  '', '', "annotation_date: $date"];
        } else {
          return undef;
        }
      }
    }
  };
}


method header {
  return '';
}

method format_result($res) {
  return (join "\t", @$res);
}
