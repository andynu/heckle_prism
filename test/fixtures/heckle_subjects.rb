class HeckleSubjects
  define_method(:defined_dynamically) { 1 }

  def label_shorthand(foo)
    {foo:}
  end
end

class HeckleSubjectsChild < HeckleSubjects
end
