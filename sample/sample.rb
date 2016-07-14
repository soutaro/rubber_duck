class Person
  attr_reader :name, :phone

  def initialize(name, phone)
    @name = name
    @phone = phone
  end

  def format
    "#{name} - #{phone}"
  end
end

class Company
  def initialize
    @people = []
  end

  def add_person(name, phone)
    @people << Person.new(name, phone)
  end

  def each_person(&block)
    @people.each &block
  end
end

company = Company.new

company.add_person "Soutaro", "080-1234-5678"

if false
  p company.format
end

company.each_person do |person|
  p person.format
end
