package PomBase::Chado::AddReciprocalIPI;

=head1 NAME

PomBase::Chado::AddReciprocalIPI - Add missing reciprocal IPI annotation
                  see: https://github.com/pombase/pombase-chado/issues/433

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::AddReciprocalIPI

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);

has organism => (is => 'rw', init_arg => undef);


sub _make_key {
  return join '-|-', @_;
}

method BUILD {
  my $organism_taxonid = undef;

  my @opt_config = ('organism-taxonid=s' => \$organism_taxonid);

  my @options_copy = @{$self->options()};

  if (!GetOptionsFromArray(\@options_copy, @opt_config)) {
    croak "option parsing failed";
  }

  if (!$organism_taxonid) {
    die "missing argument: --organism-taxonid\n";
  }

  my $organism = $self->find_organism_by_taxonid($organism_taxonid);

  if (!defined $organism) {
    die "can't find organism with taxon ID: $organism_taxonid\n";
  }

  $self->organism($organism);
}

method _add_new_ipi($protein_binding_term, $results) {
  my $new_subject = $results->{object_uniquename};
  my $new_object = $results->{subject_uniquename};

  my $pub = $self->find_or_create_pub($results->{pub_uniquename});

  my $feature = $self->find_chado_feature("$new_subject.1", 0, 0, $self->organism(), ['mRNA']);

  my $feature_cvterm =
    $self->create_feature_cvterm($feature, $protein_binding_term, $pub, 0);

  $self->add_feature_cvtermprop($feature_cvterm, 'with',
                                $self->config()->{database_name} . ':' . $new_object);

  my @prop_names = qw(community_curated assigned_by evidence curator_name curator_email canto_session
                      approver_email date);

  for my $prop_name (@prop_names) {
    my $value = $results->{$prop_name . '_value'};
    if (defined $value) {
      $self->add_feature_cvtermprop($feature_cvterm, $prop_name, $value);
    }
  }
}

method process() {
  my $chado = $self->chado();

  my $dbh = $chado->storage()->dbh();

  my $ipi_annotation_sql = <<'EOQ';
select gene.uniquename as subject_uniquename,
(select value from feature_cvtermprop fcp2 where fcp2.feature_cvterm_id = fc.feature_cvterm_id and fcp2.type_id in (select cvterm_id from cvterm where name = 'with')) as object_uniquename,
pub.uniquename as pub_uniquename,
(select value from feature_cvtermprop fcp2 where fcp2.feature_cvterm_id = fc.feature_cvterm_id and fcp2.type_id in (select cvterm_id from cvterm where name = 'community_curated')) as community_curated_value,
(select value from feature_cvtermprop fcp2 where fcp2.feature_cvterm_id = fc.feature_cvterm_id and fcp2.type_id in (select cvterm_id from cvterm where name = 'assigned_by')) as assigned_by_value,
(select value from feature_cvtermprop fcp2 where fcp2.feature_cvterm_id = fc.feature_cvterm_id and fcp2.type_id in (select cvterm_id from cvterm where name = 'curator_name')) as curator_name_value,
(select value from feature_cvtermprop fcp2 where fcp2.feature_cvterm_id = fc.feature_cvterm_id and fcp2.type_id in (select cvterm_id from cvterm where name = 'curator_email')) as curator_email_value,
(select value from feature_cvtermprop fcp2 where fcp2.feature_cvterm_id = fc.feature_cvterm_id and fcp2.type_id in (select cvterm_id from cvterm where name = 'canto_session')) as canto_session_value,
(select value from feature_cvtermprop fcp2 where fcp2.feature_cvterm_id = fc.feature_cvterm_id and fcp2.type_id in (select cvterm_id from cvterm where name = 'approver_email')) as approver_email_value,
(select value from feature_cvtermprop fcp2 where fcp2.feature_cvterm_id = fc.feature_cvterm_id and fcp2.type_id in (select cvterm_id from cvterm where name = 'date')) as date_value
from feature_cvterm fc
join pub on fc.pub_id = pub.pub_id
join feature mrna on mrna.feature_id = fc.feature_id
join feature_relationship frel on frel.subject_id = mrna.feature_id
join cvterm frel_type on frel_type.cvterm_id = frel.type_id
join feature gene on frel.object_id = gene.feature_id
join feature_cvtermprop fcp on fcp.feature_cvterm_id = fc.feature_cvterm_id
where fcp.type_id in (select cvterm_id from cvterm where name = 'evidence')
and fc.cvterm_id = (select cvterm_id from cvterm where name = 'protein binding')
and frel_type.name = 'part_of'
and fcp.value = 'Inferred from Physical Interaction' order by pub.uniquename;
EOQ

  my $sth = $dbh->prepare($ipi_annotation_sql);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my %chado_ipi_annotation = ();

  while (my $results = $sth->fetchrow_hashref()) {
    my $subject_uniquename = $results->{subject_uniquename};
    $results->{object_uniquename} =~ s/.*://;
    my $object_uniquename = $results->{object_uniquename};
    my $pub_uniquename = $results->{pub_uniquename};


    my $key = _make_key($subject_uniquename, $object_uniquename, $pub_uniquename);

    $chado_ipi_annotation{$key} = $results;
  }

  my $protein_binding_term =
    $self->find_cvterm_by_name('molecular_function', 'protein binding');

  my $missing_count = 0;

  for my $key (keys %chado_ipi_annotation) {
    my $key_results = $chado_ipi_annotation{$key};

    my $subject_uniquename = $key_results->{subject_uniquename};
    my $object_uniquename = $key_results->{object_uniquename};
    my $pub_uniquename = $key_results->{pub_uniquename};

    my $reciprocal_key = _make_key($object_uniquename, $subject_uniquename, $pub_uniquename);

    if (!exists $chado_ipi_annotation{$reciprocal_key}) {
      $self->_add_new_ipi($protein_binding_term, $key_results);
      $missing_count++;
    }
  }

  print "Added $missing_count missing reciprocal IPI annotations\n";
}

1;
