=head1 NAME

DBIx::Jello - stupidly flexible object storage

=head1 SYNOPSIS

  # Where is my DB store?
  DBIx::Jello->connect("/folder/filename.sqlite");

  # create / get a class
  my $class = DBIx::Jello->create_class( 'MyClass' );
  # $class is now 'DBIx::Jello::Class::MyClass';

  # create a new instance of the class
  my $instance = DBIx::Jello::Class::MyClass->new();
  
  # set params on the instance
  $instance->my_param('value');
  
  # get attributes out again
  my $val = $instance->my_param;

  # retrieve instance by ID
  my $another = DBIx::Jello::Class::MyClass->retrieve( $instance->id );
    
  # search for instances
  my @search = DBIx::Jello::Class::MyClass->search( my_param => "value" );

=head1 DESCRIPTION

Class::DBI is faar too much work. What I really want is to just make up
classes and their names, and to have tables dynamically created if I decide
that I want a new class, and to have columns in the table magically created
is I decide that I want a new attribute on the class.

I'm out of my tiny little mind.

=head1 METHODS

=over

=item connect( filename )

Connects DBIx::Jello to a SQLite database, creating it if it has to. A given
perl process can currently connect to only _one_ DBIx::Jello database at a
time.

=item create_class(name)

Creates a new class that can be instantiated and saved

=item all_classes

returns a list of DBIx::Jello::Class package names for all currently defined classes

=back

=head1 LIMITATIONS

We have to back onto a SQLite database. This isn't inherent in the design,
it's just that there aren't any portable database introspection methods. It's
fixable.

You have to set $DBIx::Jello::filename before use. This is easy to fix, I just
haven't.

It's completely useless in the real world. I'd be _amazed_ if your sysadmins
didn't kill you on sight for using it, for instance. It's going to play havok
with replication, for instance.

=head1 TODO

My short-term todo

=over

=item Typed storage

I'd like to store the type of the attribute as well, to compensate
for the fact that we've lost the use of the DB for typing information.

=item Ordered searching

This will be hard - SQL sorting normally can use the column type to decide
on alpha or numerical sorting. We can't do that here.

=item Clever searching

We could expose the raw SQL interface, I guess.

=item Instance deletion

=item Table cleanup

I can reasonbly remove any columns that only contain NULLs. This might be
useful, I don't know.

=item Startup

We should wrap all tables on startup. Right now, you have to call all_classes,
but I need an explicit 'connect' step to hook, and there isn't one.

=back

=head1 CAVEATS

In case you haven't figured it out, I suggest you don't use this, unless
you're _really_ sure. It's good for prototyping, I guess. The interface is
also likely to change a lot. It's just a Toy, ok?

=cut

package DBIx::Jello;
use warnings;
use strict;
use DBI;
use Carp qw( croak );

our $VERSION = 0.00001;

use DBIx::Jello::Class;

my $filename;
my $dbh;

sub connect {
  my $class = shift;
  my $set = shift;
  croak("Can't reconnect to a different database (currently $filename)")
    if ($filename and $filename ne $set);
  $filename = $set;
  $class->all_classes();
}

sub dbh {
  my $class = shift;
  croak("DBIx::Jello not connected") unless $filename;
  $dbh ||= DBI->connect(
    "dbi:SQLite:$filename", undef, undef,
    { PrintError => 0, RaiseError => 1 },
  );
}

sub reset {
  $dbh->disconnect if $dbh;
  undef $dbh;
  unlink($filename);
}

sub create_class {
  my ($class, $cname) = @_;

  my $wrapped = DBIx::Jello->_wrap_class($cname);
  
  my $existing = $class->dbh->selectall_arrayref(
    "SELECT name FROM SQLITE_MASTER WHERE type=? AND name=?", undef, 'table', $wrapped->table);

  unless ($existing->[0]) {
    $class->dbh->do("CREATE TABLE ".$wrapped->table." (id)"); # typing is for losers
  }
  return $wrapped;
}

# returns a list of all classnames
sub all_classes {
  my $class = shift;
  my $list = $class->dbh->selectall_arrayref(
    "SELECT name FROM SQLITE_MASTER WHERE TYPE=?", undef, 'table'
  );
  return map { $class->_wrap_class($_->[0]) } @$list;
}

# creates a wrapper for an existing class.
sub _wrap_class {
  my ($class, $cname) = @_;
  $cname = ucfirst($cname);
  croak( "bad class name '$cname'" ) unless $cname =~ /^[\w_]+$/;
  my $package = "DBIx::Jello::Class::$cname";
  no strict 'refs';
  # if there's already a class, return it
  return $package if %{$package."::"};
  @{ $package."::ISA" } = ( "DBIx::Jello::Class" );
  *{ $package."::table" } = sub { lc($cname) };
  return $package;
}

1;
