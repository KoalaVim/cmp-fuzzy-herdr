return function(a, b)
	if a.source.name ~= 'fuzzy_herdr' or b.source.name ~= 'fuzzy_herdr' then
		return nil
	end
	local x, y = a.completion_item, b.completion_item
	if x.data.score ~= y.data.score then
		return x.data.score > y.data.score
	end
	if #x.label ~= #y.label then
		return #x.label < #y.label
	end
	if x.label ~= y.label then
		return x.label < y.label
	end
end
