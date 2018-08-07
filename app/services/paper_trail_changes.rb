class PaperTrailChanges

  def initialize(object)
    @object = object
  end

  # Returns:
  # [
  #   { timestamp => { attribute: [before_value, after_value] } },
  #   { timestamp => { attribute: [before_value, after_value] } },
  #   ...,
  # ]
  def changes
    # first item of versions is a blank "create" record, which reifies to `nil`
    all_versions = @object.versions.drop(1).map(&:reify) + [@object]
    all_versions.each_cons(2).each_with_object([]) do |(before, after), acc|
      before.freeze && after.freeze
      acc << [User.find_by(id: after.whodunnit)&.username, after.updated_at, diff(before, after)]
    end
  end

  private

  def diff(before, after)
    updated = before.dup
    updated.changes_applied # reset changes
    updated.assign_attributes(after.attributes.except(*%w[id created_at updated_at]))
    updated.changes
  end

end
