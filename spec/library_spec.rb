require 'tmpdir'
require 'yard'

describe Solargraph::Library do
  it "raises an exception for unknown filenames" do
    library = Solargraph::Library.new
    expect {
      library.checkout 'invalid_filename.rb'
    }.to raise_error(Solargraph::FileNotFoundError)
  end

  it "ignores created files that are not in the workspace" do
    library = Solargraph::Library.new
    result = library.create('file.rb', 'a = b')
    expect(result).to be(false)
    expect {
      library.checkout 'file.rb'
    }.to raise_error(Solargraph::FileNotFoundError)
  end

  it "does not open created files in the workspace" do
    Dir.mktmpdir do |temp_dir_path|
      # Ensure we resolve any symlinks to their real path
      workspace_path = File.realpath(temp_dir_path)
      file_path = File.join(workspace_path, 'file.rb')
      File.write(file_path, 'a = b')
      library = Solargraph::Library.load(workspace_path)
      result = library.create(file_path, File.read(file_path))
      expect(result).to be(true)
      expect(library.open?(file_path)).to be(false)
    end
  end

  it "raises an exception for files that do not exist" do
    Dir.mktmpdir do |temp_dir_path|
      # Ensure we resolve any symlinks to their real path
      workspace_path = File.realpath(temp_dir_path)
      file_path = File.join(workspace_path, 'not_real.rb')
      library = Solargraph::Library.load(workspace_path)
      expect {
        library.checkout file_path
      }.to raise_error(Solargraph::FileNotFoundError)
    end
  end

  it "opens an attached file" do
    library = Solargraph::Library.new
    library.attach Solargraph::Source.load_string('a = b', 'file.rb')
    expect(library.open?('file.rb')).to be(true)
    expect {
      source = library.checkout('file.rb')
    }.not_to raise_error
  end

  it "closes a detached file" do
    library = Solargraph::Library.new
    library.attach(Solargraph::Source.load_string('a = b', 'file.rb', 0))
    library.detach 'file.rb'
    expect(library.open?('file.rb')).to be(false)
    expect {
      library.checkout 'file.rb'
    }.to raise_error(Solargraph::FileNotFoundError)
  end

  it "deletes a file from the workspace" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'file.rb')
      File.write(file, 'a = b')
      library = Solargraph::Library.load(dir)
      library.attach Solargraph::Source.load(file)
      expect {
        library.checkout file
      }.not_to raise_error
      File.unlink file
      library.delete file
      expect {
        library.checkout file
      }.to raise_error(Solargraph::FileNotFoundError)
    end
  end

  it "makes a closed file unavailable if it doesn't exist on disk" do
    library = Solargraph::Library.new
    library.attach Solargraph::Source.load_string('a = b', 'file.rb', 0)
    expect {
      library.checkout 'file.rb'
    }.not_to raise_error
    library.close 'file.rb'
    expect {
      library.checkout 'file.rb'
    }.to raise_error(Solargraph::FileNotFoundError)
  end

  it "keeps a closed file available if it exists in the workspace" do
    library = Solargraph::Library.load('spec/fixtures/workspace')
    file = 'spec/fixtures/workspace/app.rb'
    library.attach Solargraph::Source.load(file)
    expect {
      library.checkout file
    }.not_to raise_error
    library.close file
    expect {
      library.checkout file
    }.not_to raise_error
  end

  it "keeps a closed file in the workspace" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'file.rb')
      File.write file, 'a = b'
      library = Solargraph::Library.load(dir)
      library.attach Solargraph::Source.load(file)
      expect {
        library.checkout file
      }.not_to raise_error
      library.close file
      expect(library.open?(file)).to be(false)
      expect(library.contain?(file)).to be(true)
    end
  end

  it "returns a Completion" do
    library = Solargraph::Library.new
    library.attach Solargraph::Source.load_string(%(
      x = 1
      x
    ), 'file.rb', 0)
    completion = library.completions_at('file.rb', 2, 7)
    expect(completion).to be_a(Solargraph::SourceMap::Completion)
    expect(completion.pins.map(&:name)).to include('x')
  end

  it "gets definitions from a file" do
    library = Solargraph::Library.new
    src = Solargraph::Source.load_string %(
      class Foo
        def bar
        end
      end
    ), 'file.rb', 0
    library.attach src
    paths = library.definitions_at('file.rb', 2, 13).map(&:path)
    expect(paths).to include('Foo#bar')
  end

  it "signifies method arguments" do
    library = Solargraph::Library.new
    src = Solargraph::Source.load_string %(
      class Foo
        def bar baz, key: ''
        end
      end
      Foo.new.bar()
    ), 'file.rb', 0
    library.attach src
    pins = library.signatures_at('file.rb', 5, 18)
    expect(pins.length).to eq(1)
    expect(pins.first.path).to eq('Foo#bar')
  end

  it "ignores invalid filenames in create_from_disk" do
    library = Solargraph::Library.new
    filename = 'not_a_real_file.rb'
    expect(library.create_from_disk(filename)).to be(false)
    expect(library.contain?(filename)).to be(false)
  end

  it "adds mergeable files to the workspace in create_from_disk" do
    Dir.mktmpdir do |temp_dir_path|
      # Ensure we resolve any symlinks to their real path
      workspace_path = File.realpath(temp_dir_path)
      library = Solargraph::Library.load(workspace_path)
      file_path = File.join(workspace_path, 'created.rb')
      File.write(file_path, "puts 'hello'")
      expect(library.create_from_disk(file_path)).to be(true)
      expect(library.contain?(file_path)).to be(true)
    end
  end

  it "ignores non-mergeable files in create_from_disk" do
    Dir.mktmpdir do |dir|
      library = Solargraph::Library.load(dir)
      filename = File.join(dir, 'created.txt')
      File.write(filename, "puts 'hello'")
      expect(library.create_from_disk(filename)).to be(false)
      expect(library.contain?(filename)).to be(false)
    end
  end

  it "diagnoses files" do
    library = Solargraph::Library.new
    src = Solargraph::Source.load_string(%(
      puts 'hello'
    ), 'file.rb', 0)
    library.attach src
    result = library.diagnose 'file.rb'
    expect(result).to be_a(Array)
    # @todo More tests
  end

  it "documents symbols" do
    library = Solargraph::Library.new
    src = Solargraph::Source.load_string(%(
      class Foo
        def bar
        end
      end
    ), 'file.rb', 0)
    library.attach src
    pins = library.document_symbols 'file.rb'
    expect(pins.length).to eq(2)
    expect(pins.map(&:path)).to include('Foo')
    expect(pins.map(&:path)).to include('Foo#bar')
  end

  it "collects references to an instance method symbol" do
    workspace = Solargraph::Workspace.new('*')
    library = Solargraph::Library.new(workspace)
    src1 = Solargraph::Source.load_string(%(
      class Foo
        def bar
        end
      end

      Foo.new.bar
    ), 'file1.rb', 0)
    library.merge src1
    src2 = Solargraph::Source.load_string(%(
      foo = Foo.new
      foo.bar
      class Other
        def bar; end
      end
      Other.new.bar
    ), 'file2.rb', 0)
    library.merge src2
    library.catalog
    locs = library.references_from('file2.rb', 2, 11)
    expect(locs.length).to eq(3)
    expect(locs.select{|l| l.filename == 'file2.rb' && l.range.start.line == 6}).to be_empty
  end

  it "collects references to a class method symbol" do
    workspace = Solargraph::Workspace.new('*')
    library = Solargraph::Library.new(workspace)
    src1 = Solargraph::Source.load_string(%(
      class Foo
        def self.bar
        end

        def bar
        end
      end

      Foo.bar
      Foo.new.bar
    ), 'file1.rb', 0)
    library.merge src1
    src2 = Solargraph::Source.load_string(%(
      Foo.bar
      Foo.new.bar
      class Other
        def self.bar; end
        def bar; end
      end
      Other.bar
      Other.new.bar
    ), 'file2.rb', 0)
    library.merge src2
    library.catalog
    locs = library.references_from('file2.rb', 1, 11)
    expect(locs.length).to eq(3)
    expect(locs.select{|l| l.filename == 'file1.rb' && l.range.start.line == 2}).not_to be_empty
    expect(locs.select{|l| l.filename == 'file1.rb' && l.range.start.line == 9}).not_to be_empty
    expect(locs.select{|l| l.filename == 'file2.rb' && l.range.start.line == 1}).not_to be_empty
  end

  it "collects stripped references to constant symbols" do
    workspace = Solargraph::Workspace.new('*')
    library = Solargraph::Library.new(workspace)
    src1 = Solargraph::Source.load_string(%(
      class Foo
        def bar
        end
      end
      Foo.new.bar
    ), 'file1.rb', 0)
    library.merge src1
    src2 = Solargraph::Source.load_string(%(
      class Other
        foo = Foo.new
        foo.bar
      end
    ), 'file2.rb', 0)
    library.merge src2
    library.catalog
    locs = library.references_from('file1.rb', 1, 12, strip: true)
    expect(locs.length).to eq(3)
    locs.each do |l|
      code = library.read_text(l.filename)
      o1 = Solargraph::Position.to_offset(code, l.range.start)
      o2 = Solargraph::Position.to_offset(code, l.range.ending)
      expect(code[o1..o2-1]).to eq('Foo')
    end
  end

  it "searches the core for queries" do
    library = Solargraph::Library.new
    result = library.search('String')
    expect(result).not_to be_empty
  end

  it "returns YARD documentation from the core" do
    library = Solargraph::Library.new
    result = library.document('String')
    expect(result).not_to be_empty
    expect(result.first).to be_a(YARD::CodeObjects::Base)
  end

  it "returns YARD documentation from sources" do
    library = Solargraph::Library.new
    src = Solargraph::Source.load_string(%(
      class Foo
        # My bar method
        def bar; end
      end
    ), 'test.rb', 0)
    library.attach src
    result = library.document('Foo#bar')
    expect(result).not_to be_empty
    expect(result.first).to be_a(YARD::CodeObjects::Base)
  end

  it "synchronizes sources from updaters" do
    library = Solargraph::Library.new
    src = Solargraph::Source.load_string(%(
      class Foo
      end
    ), 'test.rb', 1)
    library.attach src
    repl = %(
      class Foo
        def bar; end
      end
    )
    updater = Solargraph::Source::Updater.new(
      'test.rb',
      2,
      [Solargraph::Source::Change.new(nil, repl)]
    )
    library.attach src.synchronize(updater)
    expect(library.checkout('test.rb').code).to eq(repl)
  end

  it "finds unique references" do
    library = Solargraph::Library.new(Solargraph::Workspace.new('*'))
    src1 = Solargraph::Source.load_string(%(
      class Foo
      end
    ), 'src1.rb', 1)
    library.merge src1
    src2 = Solargraph::Source.load_string(%(
      foo = Foo.new
    ), 'src2.rb', 1)
    library.merge src2
    library.catalog
    refs = library.references_from('src2.rb', 1, 12)
    expect(refs.length).to eq(2)
  end

  it "includes method parameters in references" do
    library = Solargraph::Library.new(Solargraph::Workspace.new('*'))
    source = Solargraph::Source.load_string(%(
      class Foo
        def bar(baz)
          baz.upcase
        end
      end
    ), 'test.rb', 1)
    library.attach source
    from_def = library.references_from('test.rb', 2, 16)
    expect(from_def.length).to eq(2)
    from_ref = library.references_from('test.rb', 3, 10)
    expect(from_ref.length).to eq(2)
  end

  it "includes block parameters in references" do
    library = Solargraph::Library.new(Solargraph::Workspace.new('*'))
    source = Solargraph::Source.load_string(%(
      100.times do |foo|
        puts foo
      end
    ), 'test.rb', 1)
    library.attach source
    from_def = library.references_from('test.rb', 1, 20)
    expect(from_def.length).to eq(2)
    from_ref = library.references_from('test.rb', 2, 13)
    expect(from_ref.length).to eq(2)
  end
end
