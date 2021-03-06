describe RubyXsd do
  describe "XMLSchema root validation" do
    it "rejects non-schema root" do
      ex = assert_raises RuntimeError do
        RubyXsd.models_from "<non-xs></non-xs>"
      end
      assert_equal "Invalid XMLSchema root", ex.message
    end

    it "rejects schema root without XMLSchema namespace" do
      ex = assert_raises RuntimeError do
        RubyXsd.models_from "<schema></schema>"
      end
      assert_equal "Missing XMLSchema namespace", ex.message
    end

    it "rejects schema with wrong XMLSchema namespace" do
      ex = assert_raises RuntimeError do
        RubyXsd.models_from "<xs:schema xmlns:xs='wrong'></xs:schema>"
      end
      assert_equal "Wrong XMLSchema namespace", ex.message
    end
  end

  let(:schema) {
    "<xs:schema xmlns:xs='#{ClassMaker::XMLSchemaNS}'>%s</xs:schema>"
  }

  describe "simple elements" do
    let(:template) {
      schema % "<xs:element name='%s' type='%s' />"
    }

    it "defines object attributes" do
      RubyXsd.models_from template % [ "xsd_attr", "xs:string" ]
      RubyXsd.new.must_respond_to :xsd_attr
      RubyXsd.new.must_respond_to :xsd_attr=
    end
  end

  describe "complex elements" do
    let(:template) {
      schema % "<xs:element name='%s'>%s</xs:element>"
    }

    let(:class_template) {
      template % [ "xsd_complex", "" ]
    }

    let(:class_with_attrs_template) {
      template % [ "xsd_complex_with_attr", %{
        <xs:complexType>
          <xs:sequence>
            <xs:element name="foo" type="xs:string" />
            <xs:element name="bar" type="xs:string" />
          </xs:sequence>
        </xs:complexType>
      }]
    }

    it "defines a new Class" do
      RubyXsd.models_from class_template
      defined?(XsdComplex).must_be :==, "constant"
      XsdComplex.class.must_be :==, Class
    end

    it "defines class attributes" do
      RubyXsd.models_from class_with_attrs_template

      defined?(XsdComplexWithAttr).must_be :==, "constant"
      XsdComplexWithAttr.class.must_be :==, Class

      obj = XsdComplexWithAttr.new
      [ :foo, :foo=, :bar, :bar= ].each { |m|
        obj.must_respond_to m
      }
    end
  end

  describe "complex roots" do
    let(:template) {
      schema % "<xs:complexType name='%s'>%s</xs:complexType>"
    }

    let(:complex_root) {
      template % [ "complex_root", "" ]
    }

    let(:root_with_attrs_template) {
      template % [ "xsd_root_with_attr", %{
        <xs:sequence>
          <xs:element name="foo" type="xs:string" />
          <xs:element name="bar" type="xs:string" />
        </xs:sequence>
      }]
    }

    it "defines new class" do
      RubyXsd.models_from complex_root
      defined?(ComplexRoot).must_be :==, "constant"
      ComplexRoot.class.must_be :==, Class
    end

    it "defines class attributes" do
      RubyXsd.models_from root_with_attrs_template

      defined?(XsdRootWithAttr).must_be :==, "constant"
      XsdRootWithAttr.class.must_be :==, Class

      obj = XsdRootWithAttr.new
      [ :foo, :foo=, :bar, :bar= ].each { |m|
        obj.must_respond_to m
      }
    end
  end

  describe "nested classes" do
    let(:template) {
      schema % %{
        <xs:complexType name='%s'>
          <xs:sequence>%s</xs:sequence>
        </xs:complexType>
      }
    }

    let(:elements_template) {
      template % [ "elem_parent", %{
        <xs:element name="nested1"></xs:element>
        <xs:element name="nested2"></xs:element>
      }]
    }

    let(:elements_template_with_attr) {
      template % [ "elem_parent_with_attr", %{
        <xs:element name="nested1">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="foo" type="xs:string" />
            </xs:sequence>
          </xs:complexType>
        </xs:element>
        <xs:element name="nested2">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="bar" type="xs:string" />
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      }]
    }

    it "nests with complex elements" do
      RubyXsd.models_from elements_template

      defined?(ElemParent).must_be :==, "constant"
      ElemParent.class.must_be :==, Class

      defined?(Nested1).must_be_nil
      defined?(ElemParent::Nested1).must_be :==, "constant"
      ElemParent::Nested1.class.must_be :==, Class

      defined?(Nested2).must_be_nil
      defined?(ElemParent::Nested2).must_be :==, "constant"
      ElemParent::Nested2.class.must_be :==, Class
    end

    it "nests with complex elements" do
      RubyXsd.models_from elements_template_with_attr

      ElemParentWithAttr::Nested1.new.must_respond_to :foo
      ElemParentWithAttr::Nested1.new.wont_respond_to :bar

      ElemParentWithAttr::Nested2.new.wont_respond_to :foo
      ElemParentWithAttr::Nested2.new.must_respond_to :bar
    end
  end

  describe "restrictions" do
    describe "compact form" do
      let(:template) {
        schema % %{
          <xs:simpleType name="foo">
            <xs:restriction base="xs:%s">%s</xs:restriction>
          </xs:simpleType>
        }
      }

      let(:make_bar) {
        class Bar
          include ActiveModel::Validations
          attr_accessor :baz
          validates :baz, foo: true
        end
      }

      after do
        [ :FooValidator, :Bar ].each { |const|
          Object.send(:remove_const, const) if Object.const_defined? const
        }
      end

      it "creates validator" do
        RubyXsd.models_from template % [ "string", "" ]

        defined?(FooValidator).must_be :==, "constant"
        FooValidator.superclass.must_be :==, ActiveModel::EachValidator
      end

      it "validates string type" do
        RubyXsd.models_from template % [ "string", "" ]
        make_bar

        bar = Bar.new
        bar.baz = 1
        bar.valid?.wont_equal true

        bar.baz = "1"
        bar.valid?.must_equal true
      end

      it "validates integer type" do
        RubyXsd.models_from template % [ "integer", "" ]
        make_bar

        bar = Bar.new
        bar.baz = 1
        bar.valid?.must_equal true

        bar.baz = "1"
        bar.valid?.wont_equal true
      end

      describe "Whitespace handling" do
        let(:whitespace_schema) {
          template % [ "string", %{<xs:whiteSpace value="%s" />} ]
        }

        let(:whitespace_string) {
          "  abc  de\tfg\n\rhi jk   "
        }

        let(:replaced_string) {
          "  abc  de fg  hi jk   "
        }

        let(:collapsed_string) {
          "abc de fg hi jk"
        }

        def apply action
          xsd = whitespace_schema % action
          RubyXsd.models_from xsd
          make_bar

          bar = Bar.new
          bar.baz = whitespace_string
          bar.valid?
          bar
        end

        it "preserves" do
          apply("preserve").baz.must_equal whitespace_string
        end

        it "replaces" do
          apply("replace").baz.must_equal replaced_string
        end

        it "collapses" do
          apply("collapse").baz.must_equal collapsed_string
        end
      end

      describe "Enumeration handling" do
        def enum_xsd values
          enum_str = ""
          values.each do |v|
            enum_str << %{<xs:enumeration value="#{v}" />}
          end
          template % [ "string", enum_str ]
        end

        let(:range) { (5..10).to_a + (20..25).to_a }
        let(:out_of_range) { (1..30).to_a - range }
        let(:bar) { Bar.new }

        before do
          RubyXsd.models_from enum_xsd range
          make_bar
        end

        it "accepts value in range" do
          range.each { |val|
            bar.baz = val.to_s
            bar.valid?.must_equal true, message: bar.errors.messages
          }
        end

        it "rejects value out of range" do
          out_of_range.each { |val|
            bar.baz = val.to_s
            bar.valid?.wont_equal true, message: bar.errors.messages

            range_str = range.collect{|v| v.to_s}.to_s
            bar.errors.messages[:baz].first
            .must_equal "#{val}: not in #{range_str}"
          }
        end
      end

      describe "Regexp handling" do
        let(:pattern) { '\w{3}[X-Z]{3}_\d{6}' }

        let(:pattern_schema) {
          template % [ "string", %{<xs:pattern value="#{pattern}" />} ]
        }

        let(:bar) {
          inst = Bar.new
          inst.baz = "AbcXYZ_123456"
          inst
        }

        before do
          RubyXsd.models_from pattern_schema
          make_bar
        end

        it "accepts value matching pattern" do
          bar.valid?.must_equal true, message: bar.errors.messages
        end

        it "rejects value not matching pattern" do
          bar.baz = "not matches"
          bar.valid?.wont_equal true, message: bar.errors.messages
          bar.errors.messages[:baz].first
            .must_equal "#{bar.baz}: not matching #{pattern}"
        end
      end
    end
  end
end
