use perl5i::2;

use Test::More tests => 4;

BEGIN { use_ok('PomBase::Role::FeatureCvtermCreator') };
BEGIN { use_ok('PomBase::Chado::LoadFeat') };
BEGIN { use_ok('PomBase::Chado::QualifierLoad') };
BEGIN { use_ok('PomBase::Chado::ExtensionProcessor') };
