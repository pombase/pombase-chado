package PomBase::Role::CvQuery;

=head1 NAME

PomBase::Role::CvQuery - Code for querying the cvterm and cv tables

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Role::CvQuery

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose::Role;

requires 'chado';

method get_cv($cv_name)
{
  state $cache = {};

  return $cache->{$cv_name} //
         ($cache->{$cv_name} =
           $self->chado()->resultset('Cv::Cv')->find({ name => $cv_name }));
}

method get_cvterm($cv_name, $cvterm_name)
{
  my $cv = $self->get_cv($cv_name);

  if (!defined $cv) {
    warn "no such CV: $cv_name\n";
    return undef;
  }

  state $cache = {};

  if (exists $cache->{$cv_name}->{$cvterm_name}) {
    return $cache->{$cv_name}->{$cvterm_name};
  }

  my $cvterm_rs = $self->chado()->resultset('Cv::Cvterm');
  my $cvterm = $cvterm_rs->find({ name => $cvterm_name,
                                  cv_id => $cv->cv_id() });

  $cache->{$cv_name}->{$cvterm_name} = $cvterm;

  return $cvterm;
}

# find cvterm by query with name or cvtermsynonym
method find_cvterm_by_name($cv, $term_name, %options) {
  if (!ref $cv) {
    $cv = $self->get_cv($cv);
  }

  state $cache = {};

  if (exists $cache->{$cv->name()}->{$term_name}) {
    return $cache->{$cv->name()}->{$term_name};
  }

  my %search_options = ();

  if ($options{prefetch_dbxref}) {
    $search_options{prefetch} = { dbxref => 'db' };
  }

  my $cvterm_rs = $self->chado()->resultset('Cv::Cvterm');
  my $cvterm = $cvterm_rs->find({ name => $term_name, cv_id => $cv->cv_id() },
                                { %search_options });

  if (defined $cvterm) {
    $cache->{$cv->name()}->{$term_name} = $cvterm;
    return $cvterm;
  } else {
    my $synonym_rs = $self->chado()->resultset('Cv::Cvtermsynonym');
    my $exact_cvterm = $self->get_cvterm('synonym_type', 'exact');
    my $search_rs =
      $synonym_rs->search({ synonym => $term_name,
                            type_id => $exact_cvterm->cvterm_id(),
                            'cvterm.cv_id' => $cv->cv_id(),
                          },
                          {
                            join => 'cvterm'
                          });

    if ($search_rs->count() > 1) {
      die "more than one exact cvtermsynonym found for $term_name";
    } else {
      my $exact_synonym = $search_rs->first();

      if (defined $exact_synonym) {
        warn "      found as synonym: $term_name\n" if $self->verbose();
        return $cvterm_rs->find($exact_synonym->cvterm_id());
      } else {
        # try non-exact synonyms
        $search_rs = $synonym_rs->search({ synonym => $term_name,
                                           'cvterm.cv_id' => $cv->cv_id(),
                                         },
                                         {
                                           join => 'cvterm'
                                         });

        if ($search_rs->count() > 1) {
          die "more than one cvtermsynonym found for $term_name";
        } else {
          my $synonym = $search_rs->first();

          if (defined $synonym) {
            warn "      found as synonym (type: ", $synonym->type()->name(),
              "): $term_name\n" if $self->verbose();
            return $cvterm_rs->find($synonym->cvterm_id());
          } else {
            return undef;
          }
        }
      }
    }
  }

}

method find_cvterm_by_term_id($term_id)
{
  state $cache = {};

  if (exists $cache->{$term_id}) {
    return $cache->{$term_id};
  }

  if ($term_id =~ /(.*):(.*)/) {
    my $db_name = $1;
    my $dbxref_accession = $2;

    my $chado = $self->chado();
    my $db = $chado->resultset('General::Db')->find({ name => $db_name });

    my @cvterms = $chado->resultset('General::Dbxref')
      ->search({ db_id => $db->db_id(),
                 accession => $dbxref_accession })
      ->search_related('cvterm')
      ->all();


    if (@cvterms > 1) {
      die "more than one cvterm for dbxref ($term_id)\n";
    } else {
      if (@cvterms == 1) {
        $cache->{$term_id} = $cvterms[0];
        return $cvterms[0];
      } else {
        return undef;
      }
    }
  } else {
    die "database ID ($term_id) doesn't contain a colon";
  }
}


1;
