=head1 NAME

DBIx::Jello::Class - persisted DBIx::Jello-based classes

=head1 DESCRIPTION

You don't use DBIx::Jello::Class directly, you'll be given subclasses of it
from L<DBIx::Jello> proper.

=cut

package DBIx::Jello::Class;
use warnings;
use strict;
use Carp qw( croak );
use Data::UUID;

=head1 CLASS METHODS

Your generated classes will have the following methods

=over

=item dbh()

returns the dbh we're connected to

=cut

# must figure out how to get rid of this.
sub dbh { DBIx::Jello->dbh }

=item table()

returns the table name in the database.

=cut

# this gets overridden in the dynamicly-created subclasses.
sub table {
  Carp::croak( "You can't create instances of DBIx::Jello::Class, only of its subclasses");
}

my $_singleton_cache;

# don't use!!
sub _clear_singleton_cache {
  $_singleton_cache = {};
}

=item new( key => value, key => value )

Create a new instance of this class. Any key/value pairs will be used as
the initial state of the instance.

=cut

sub new {
  my $class = shift;
  my $id = Data::UUID->new->create_str;
  $class->dbh->do("INSERT INTO ".$class->table." (id) VALUES (?)", undef, $id);
  # TODO - creation does an insert, then a select. (and an update if %set)
  # this is overkill - try to just do an insert.
  my $self = $class->retrieve($id);
  return $self->set(@_);
}

=item retrieve(id)

retrieve an instance of the class by ID

=cut

sub retrieve {
  my ($class, $id) = @_;
  my $self;
  unless ($self = $_singleton_cache->{$id}) {
    $self = $_singleton_cache->{$id} = bless {}, $class;
    $self->{id} = $id;
    $self->_refresh;
    weaken( $_singleton_cache->{$id} );
  }
  return $self;
}

=item search( ... )

Search for instances

=cut

sub search {
  my ($class, %params) = @_;
  my $sql = "SELECT id FROM ".$class->table;
  my $where = join(" AND ", map { "$_ = ?" } (keys %params) );
  $sql .= " WHERE $where" if $where;

  my $list = $class->dbh->selectall_arrayref($sql, undef, values %params);
  return map { $class->retrieve( $_->[0] ) } @$list;
}

=back

=head1 INSTANCE METHODS

=over

=item id

returns the (read-only) ID of the instance

=cut

sub id {
  my $self = shift;
  croak("can't set ID") if @_;
  return $self->{id};
}

=item get( param )

returns the value of the named parameter of the instance

=cut

sub get {
  my ($self, $attr) = @_;
  return $self->{data}->{$attr};
}

=item set( param, value [ param, value, param, value ... ] )

sets the named param to the passed value. Can be passed a hash to set
many params.

=cut

sub set {
  my ($self, %set) = @_;
  $self->{data} ||= {};
  for my $key (keys %set) {
    unless (exists $self->{data}->{$key}) {
      croak( "bad attribute name" ) unless $key =~ /^[\w_]+$/;
      $self->dbh->do("ALTER TABLE ".$self->table." ADD COLUMN `$key`");
    }
    $self->{data}->{$key} = $set{$key};
  }
  return $self->_update();
}

=back

=cut

=head1 AUTOLOAD

DBIx::Jello::Class objects provide an AUTOLOAD method that can get/set any parameter.
Just call $instance->foo( 'bar' ) to set the 'foo' param to 'bar', and
$instance->foo() to get the value of the foo param.

=cut

our $AUTOLOAD;
sub DESTROY{}
sub AUTOLOAD {
  my $self = shift;
  my ($param) = $AUTOLOAD =~ /([^:]+)$/ or die "Can't parse AUTOLOAD string $AUTOLOAD";
  Carp::croak("Can't use '$param' as a class method on $self") unless ref($self);

  if (@_) {
    return $self->set($param, @_);
  } else {
    return $self->get($param);
  }  
}

sub _refresh {
  my $self = shift;
  my $instances = $self->dbh->selectall_arrayref(
    "SELECT * FROM ".$self->table." WHERE id = ?", { Slice => {} }, $self->id);
  $self->{data} = $instances->[0] or die "no such instance";
  return $self;
}

sub _update {
  my $self = shift;
  my @keys = grep { $_ ne 'id' } keys %{ $self->{data} };
  return $self unless @keys;
  my @values = map { $self->{data}{$_} } @keys;
  my $update = join ", ", map( { "$_ = ?" } @keys );
  $self->dbh->do("UPDATE ".$self->table." SET $update WHERE id=?", undef, @values, $self->id );
  return $self->_refresh;
}


=head1 AUTHOR

Tom Insam <tom@jerakeen.org>

=cut

1;
