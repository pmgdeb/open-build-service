# TODO: Please overwrite this comment with something explaining the model target
class Kiwi::Image < ApplicationRecord
  #### Includes and extends

  #### Constants
  DEFAULT_KIWI_BODY = '<?xml version="1.0" encoding="utf-8"?>
<image schemaversion="6.2" name="suse-13.2-live">
  <description type="system">
  </description>
  <preferences>
    <type image="oem" primary="true" boot="oemboot/suse-13.2"/>
  </preferences>
  <packages type="bootstrap">
  </packages>
</image>
'

  #### Self config

  #### Attributes

  #### Associations macros (Belongs to, Has one, Has many)
  has_one :package, foreign_key: 'kiwi_image_id', dependent: :nullify, inverse_of: :kiwi_image
  has_many :repositories, -> { order(order: :asc) }, dependent: :destroy, index_errors: true

  #### Callbacks macros: before_save, after_save, etc.

  #### Scopes (first the default_scope macro if is used)

  #### Validations macros
  validates :name, presence: true
  accepts_nested_attributes_for :repositories

  #### Class methods using self. (public and then private)

  #### To define class methods as private use private_class_method
  #### private

  #### Instance methods (public and then protected/private)

  #### Alias of methods
  def self.build_from_xml(xml_string, md5)
    xml = Xmlhash.parse(xml_string)
    new_image = new(name: xml['name'], md5_last_revision: md5)
    order = 1
    repositories = xml["repository"]
    repositories = [xml["repository"]] if xml["repository"].is_a?(Hash)
    repositories.each do |repository|
      attributes = {
        repo_type:   repository['type'],
        source_path: repository['source']['path'],
        priority:    repository['priority'],
        order:       order,
        alias:       repository['alias'],
        replaceable: repository['status'] == 'replaceable',
        username:    repository['username'],
        password:    repository['password']
      }
      attributes['imageinclude'] = repository['imageinclude'] == 'true' if repository.key?('imageinclude')
      attributes['prefer_license'] = repository['prefer-license'] == 'true' if repository.key?('prefer-license')

      new_image.repositories.build(attributes)
      order += 1
    end
    new_image
  end

  def to_xml
    if package
      kiwi_file = package.kiwi_image_file
      return nil unless kiwi_file
      kiwi_body = package.source_file(kiwi_file)
    else
      kiwi_body = DEFAULT_KIWI_BODY
    end

    doc = Nokogiri::XML::DocumentFragment.parse(kiwi_body)
    image = doc.at_css('image')

    return nil unless image && image.first_element_child

    doc.xpath("image/repository").remove
    xml_repos = repositories.map(&:to_xml).join("\n")
    image.first_element_child.after(xml_repos)

    # Reparser for pretty printing
    Nokogiri::XML(doc.to_xml, &:noblanks).to_xml
  end

  def write_to_backend
    return false unless package

    Package.transaction do
      file_name = package.kiwi_image_file || "#{package.name}.kiwi"
      package.save_file({ filename: file_name, file: to_xml })
      self.md5_last_revision = package.kiwi_file_md5
      save!
    end
  end

  def outdated?
    return false unless package

    package.kiwi_image_outdated?
  end
end

# == Schema Information
#
# Table name: kiwi_images
#
#  id                :integer          not null, primary key
#  name              :string(255)
#  md5_last_revision :string(32)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#