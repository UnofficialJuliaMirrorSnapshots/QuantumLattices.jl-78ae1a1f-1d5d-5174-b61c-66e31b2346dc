module AlgebraOverFields

using Printf: @printf,@sprintf
using ...Interfaces: dimension
using ...Prerequisites: atol,rtol,Float
using ...Prerequisites.NamedVectors: NamedVector
using ...Prerequisites.TypeTraits: efficientoperations
using ...Prerequisites.CompositeStructures: CompositeTuple
using ..Combinatorics: AbstractCombinatorics
using ..VectorSpaces: GradedTables,GradedVectorSpace,DirectVectorSpace,TabledIndices

import ...Interfaces: rank,add!,sub!,mul!,div!,⊗,⋅,sequence,permute

export SimpleID,ID
export IdSpace
export Element,ScalarElement,Elements
export scalartype,idtype,rawelement

"""
    SimpleID <: NamedVector

A simple id is the building block of the id system of an algebra over a field.
"""
abstract type SimpleID <: NamedVector end

"""
    ID(ids::NTuple{N,SimpleID}) where N
    ID(ids::SimpleID...)
    ID(::Type{SID},attrs::Vararg{NTuple{N},M}) where {SID<:SimpleID,N,M}

The id system of an algebra over a field.
"""
struct ID{T<:Tuple{Vararg{SimpleID}}} <: CompositeTuple{T}
    contents::T
    ID(ids::NTuple{N,SimpleID}) where N=new{typeof(ids)}(ids)
end
ID(ids::SimpleID...)=ID(ids)
@generated function ID(::Type{SID},attrs::Vararg{NTuple{N,Any},M}) where {SID<:SimpleID,N,M}
    exprs=[]
    for i=1:N
        args=[:(attrs[$j][$i]) for j=1:M]
        push!(exprs,:(SID($(args...))))
    end
    return :(ID($(exprs...)))
end

"""
    propertynames(::Type{I},private::Bool=false) where I<:ID -> Tuple

Get the property names of a composite id.
"""
Base.propertynames(::Type{I},private::Bool=false) where I<:ID=idpropertynames(I,Val(private))
@generated function idpropertynames(::Type{I},::Val{true}) where I<:ID
    exprs=[QuoteNode(Symbol(name,'s')) for name in fieldtype(I,:contents)|>eltype|>fieldnames]
    return Expr(:tuple,QuoteNode(:contents),exprs...)
end
@generated function idpropertynames(::Type{I},::Val{false}) where I<:ID
    exprs=[QuoteNode(Symbol(name,'s')) for name in fieldtype(I,:contents)|>eltype|>fieldnames]
    return Expr(:tuple,exprs...)
end

"""
    getproperty(cid::ID,name::Symbol)

Get the property of a composite id.
"""
Base.getproperty(cid::ID,name::Symbol)=name==:contents ? getfield(cid,:contents) : idgetproperty(cid,Val(name),Val(cid|>typeof|>propertynames))
@generated function idgetproperty(cid::ID{<:NTuple{N,SimpleID}},::Val{name},::Val{names}) where {N,name,names}
    index=findfirst(isequal(name),names)::Int
    exprs=[:(getfield(cid[$i],$index)) for i=1:N]
    return Expr(:tuple,exprs...)
end

"""
    promote_rule(::Type{I1},::Type{I2}) where {I1<:ID,I2<:ID}

Define the promote rule for ID types.
"""
function Base.promote_rule(::Type{I1},::Type{I2}) where {I1<:ID,I2<:ID}
    I1<:I2 && return I2
    I2<:I1 && return I1
    return ID
end

"""
    show(io::IO,cid::ID)

Show a composite id.
"""
Base.show(io::IO,cid::ID)=@printf io "%s(%s)" cid|>typeof|>nameof join(cid,",")

"""
    isless(cid1::ID,cid2::ID) -> Bool
    <(cid1::ID,cid2::ID) -> Bool

Compare two ids and judge whether the first is less than the second.

We assume that ids with smaller ranks are always less than those with higher ranks. If two ids are of the same rank, the comparison goes just like that between tuples.
"""
function Base.isless(cid1::ID,cid2::ID)
    r1,r2=cid1|>rank,cid2|>rank
    r1<r2 ? true : r1>r2 ? false : isless(convert(Tuple,cid1),convert(Tuple,cid2))
end
function Base.:<(cid1::ID,cid2::ID)
    r1,r2=cid1|>rank,cid2|>rank
    r1<r2 ? true : r1>r2 ? false : convert(Tuple,cid1)<convert(Tuple,cid2)
end

"""
    rank(id::ID) -> Int
    rank(::Type{<:ID}) -> Any
    rank(::Type{<:ID{T}}) where T<:Tuple{Vararg{SimpleID}} -> Int

Get the rank of a composite id.
"""
rank(id::ID)=id|>typeof|>rank
rank(::Type{<:ID})=Any
rank(::Type{<:ID{<:Tuple{Vararg{SimpleID,N}}}}) where N=N

"""
    *(sid1::SimpleID,sid2::SimpleID) -> ID
    *(sid::SimpleID,cid::ID) -> ID
    *(cid::ID,sid::SimpleID) -> ID
    *(cid1::ID,cid2::ID) -> ID

Get the product of the id system.
"""
Base.:*(sid1::SimpleID,sid2::SimpleID)=ID(sid1,sid2)
Base.:*(sid::SimpleID,cid::ID)=ID(sid,convert(Tuple,cid)...)
Base.:*(cid::ID,sid::SimpleID)=ID(convert(Tuple,cid)...,sid)
Base.:*(cid1::ID,cid2::ID)=ID(convert(Tuple,cid1)...,convert(Tuple,cid2)...)

"""
    IdSpace(sids::DirectVectorSpace,tables::GradedTables)
    IdSpace(::Type{M},sids::DirectVectorSpace,gs::Val{GS}) where {M<:AbstractCombinatorics,GS}

The graded id space for an algebra generated by a couple of basic simple ids.
"""
struct IdSpace{S<:DirectVectorSpace,V<:TabledIndices,T<:GradedTables{Int,V}} <: GradedVectorSpace{Int,Tuple{Vararg{Int}},V,T}
    sids::S
    tables::T
    IdSpace(sids::DirectVectorSpace,tables::GradedTables)=new{typeof(sids),valtype(tables),typeof(tables)}(sids,tables)
end
IdSpace(::Type{M},sids::DirectVectorSpace,gs::Val{GS}) where {M<:AbstractCombinatorics,GS}=IdSpace(sids,GradedTables(M,dimension(sids),gs))

"""
    getindex(idspace::IdSpace,i::Int) -> ID

Get the ith id of a idspace.
"""
Base.getindex(idspace::IdSpace,i::Int)=ID(_tuple_(idspace.sids.table,invoke(getindex,Tuple{GradedVectorSpace,Int},idspace,i)[2]))
@generated _tuple_(sids::NTuple{M,SimpleID},index::NTuple{N,Int}) where {M,N}=Expr(:tuple,[:(sids[index[$i]]) for i=1:N]...)

"""
    findfirst(id::ID,idspace::IdSpace) -> Int
    searchsortedfirst(idspace::IdSpace,id::ID) -> Int

Find the index of an id in a idspace.
"""
Base.findfirst(id::ID,idspace::IdSpace)=searchsortedfirst(idspace,id)
Base.searchsortedfirst(idspace::IdSpace,id::ID)=searchsortedfirst(idspace,(rank(id),findfirst(id,idspace.sids)))

"""
    Element{V,I<:ID}

An element of an algebra over a field.

The first and second attributes of an element must be
- `value`: the coefficient of the element
- `id::ID`: the id of the element
"""
abstract type Element{V,I<:ID} end

"""
    ScalarElement{V}

Identity element.
"""
const ScalarElement{V}=Element{V,ID{Tuple{}}}
scalartype(::Type{M}) where M<:Element=rawelement(M){M|>valtype,ID{Tuple{}}}

"""
    valtype(m::Element)
    valtype(::Type{<:Element})
    valtype(::Type{<:Element{V}}) where V

Get the type of the value of an element.

The result is also the type of the field over which the algebra is defined.
"""
Base.valtype(m::Element)=m|>typeof|>valtype
Base.valtype(::Type{<:Element})=Any
Base.valtype(::Type{<:Element{V}}) where V=V

"""
    idtype(m::Element)
    idtype(::Type{<:Element{V,I} where V}) where I<:ID
    idtype(::Type{<:Element})

The type of the id of an element.
"""
idtype(m::Element)=m|>typeof|>idtype
idtype(::Type{<:Element{V,I} where V}) where I<:ID=I
idtype(::Type{<:Element})=ID

"""
    rank(m::Element) -> Int
    rank(::Type{M}) where M<:Element -> Int

Get the rank of an element.
"""
rank(m::Element)=m|>typeof|>rank
rank(::Type{M}) where M<:Element=M|>idtype|>rank

"""
    (m1::Element,m2::Element) -> Bool
    isequal(m1::Element,m2::Element) -> Bool

Compare two elements and judge whether they are equal to each other.
"""
Base.:(==)(m1::Element,m2::Element) = ==(efficientoperations,m1,m2)
Base.isequal(m1::Element,m2::Element)=isequal(efficientoperations,m1,m2)

"""
    isapprox(m1::Element,m2::Element;atol::Real=atol,rtol::Real=rtol) -> Bool

Compare two elements and judge whether they are inexactly equivalent to each other.
"""
Base.isapprox(m1::Element,m2::Element;atol::Real=atol,rtol::Real=rtol)=isapprox(efficientoperations,Val((:value,)),m1,m2;atol=atol,rtol=rtol)

"""
    replace(m::Element;kwargs...) -> typeof(m)

Return a copy of a concrete `Element` with some of the field values replaced by the keyword arguments.
"""
Base.replace(m::Element;kwargs...)=replace(efficientoperations,m;kwargs...)

"""
    promote_rule(::Type{M1},::Type{M2}) where {M1<:Element,M2<:Element}

Define the promote rule for Element types.
"""
function Base.promote_rule(::Type{M1},::Type{M2}) where {M1<:Element,M2<:Element}
    M1<:M2 && return M2
    M2<:M1 && return M1
    v1,i1,r1=M1|>valtype,M1|>idtype,M1|>rank
    v2,i2,r2=M2|>valtype,M2|>idtype,M2|>rank
    V=promote_type(v1,v2)
    I=promote_type(i1,i2)
    M=r2==0 ? rawelement(M1) : r1==0 ? rawelement(M2) : typejoin(rawelement(M1),rawelement(M2))
    isconcretetype(I) && return M{V,I}
    I==ID && return M{V}
    return M{V,<:I}
end

"""
    rawelement(::Type{<:Element})

Get the raw name of a type of Element.
"""
rawelement(::Type{<:Element})=Element

"""
    one(::Type{M}) where {M<:Element}

Get the identity operator.
"""
function Base.one(::Type{M}) where {M<:Element}
    rtype=rawelement(M)
    vtype=isconcretetype(valtype(M)) ? valtype(M) : Int
    @assert fieldnames(rtype)==(:value,:id) "one error: not supproted type($(nameof(rtype)))."
    return rtype(one(vtype),ID())
end

"""
    convert(::Type{M},m::ScalarElement) where {M<:ScalarElement}
    convert(::Type{M},m) where {M<:ScalarElement}
    convert(::Type{M},m::Element) where {M<:Element}

1) Convert a scalar element from one type to another;
2) Convert a scalar to a scalar element;
3) Convert an element from one type to another.
"""
function Base.convert(::Type{M},m::ScalarElement) where {M<:ScalarElement}
    typeof(m)<:M && return m
    @assert fieldnames(M)==(:value,:id) "convert error: not supported type($(nameof(M)))."
    return rawelement(M)(convert(M|>valtype,m.value),m.id)
end
function Base.convert(::Type{M},m) where {M<:ScalarElement}
    @assert fieldnames(M)==(:value,:id) "convert error: not supported type($(nameof(M)))."
    return rawelement(M)(convert(M|>valtype,m),ID())
end
function Base.convert(::Type{M},m::Element) where {M<:Element}
    typeof(m)<:M && return m
    @assert idtype(m)<:idtype(M) "convert error: dismatched ID type."
    @assert rawelement(typeof(m))<:rawelement(M) "convert error: dismatched raw Element type."
    return replace(m,value=convert(valtype(M),m.value))
end

"""
    Elements{I<:ID,M<:Element} <: AbstractDict{I,M}

An set of elements of an algebra over a field.

Alias for `Dict{I<:ID,M<:Element}`. Similar iterms are automatically merged thanks to the id system.
"""
const Elements{I<:ID,M<:Element}=Dict{I,M}
"""
    Elements(ms)
    Elements(ms::Pair{I,M}...) where {I<:ID,M<:Element}
    Elements(ms::Element...)

Get the set of elements with similar items merged.
"""
Elements(ms)=Base.dict_with_eltype((K,V)->Dict{K,V},ms,eltype(ms))
function Elements(ms::Pair{I,M}...) where {I<:ID,M<:Element}
    result=Elements{I,M}()
    for (id,m) in ms result[id]=m end
    return result
end
function Elements(ms::Element...)
    result=Elements{ms|>eltype|>idtype,ms|>eltype}()
    for m in ms add!(result,m) end
    return result
end

"""
    show(io::IO,ms::Elements)

Show a set of elements.
"""
function Base.show(io::IO,ms::Elements)
    @printf io "Elements with %s entries:\n" length(ms)
    for m in values(ms)
        @printf io "  %s\n" m
    end
end

"""
    repr(ms::Elements) -> String

Get the repr representation of a set of elements.
"""
function Base.repr(ms::Elements)
    cache=[@sprintf("Elements with %s entries:",length(ms))]
    for m in ms|>values
        push!(cache,@sprintf("  %s",repr(m)))
    end
    return join(cache,"\n")
end

"""
    zero(ms::Elements) -> Nothing
    zero(::Type{<:Elements}) -> Nothing

Get a zero set of elements.

A zero set of elements is defined to be the one with no elements.
"""
Base.zero(ms::Elements)=ms|>typeof|>zero
Base.zero(::Type{<:Elements})=nothing

"""
    ==(ms::Elements,::Nothing) -> Bool
    ==(::Nothing,ms::Elements) -> Bool
    isequal(ms::Elements,::Nothing) -> Bool
    isequal(::Nothing,ms::Elements) -> Bool
"""
Base.:(==)(ms::Elements,::Nothing)=length(ms)==0
Base.:(==)(::Nothing,ms::Elements)=length(ms)==0
Base.isequal(ms::Elements,::Nothing)=length(ms)==0
Base.isequal(::Nothing,ms::Elements)=length(ms)==0

"""
    add!(ms::Elements) -> typeof(ms)
    add!(ms::Elements,::Nothing) -> typeof(ms)
    add!(ms::Elements,m) -> typeof(ms)
    add!(ms::Elements,m::Element) -> typeof(ms)
    add!(ms::Elements,mms::Elements) -> typeof(ms)

Get the inplace addition of elements to a set.
"""
add!(ms::Elements)=ms
add!(ms::Elements,::Nothing)=ms
add!(ms::Elements,m)=add!(ms,convert(scalartype(ms|>valtype),m))
function add!(ms::Elements,m::ScalarElement)
    m=convert(scalartype(ms|>valtype),m)
    old=get(ms,m.id,nothing)
    new=old===nothing ? m : replace(old,value=old.value+m.value)
    abs(new.value)==0.0 ? delete!(ms,m.id) : ms[m.id]=new
    return ms
end
function add!(ms::Elements,m::Element)
    m=convert(ms|>valtype,m)
    old=get(ms,m.id,nothing)
    new=old===nothing ? m : replace(old,value=old.value+m.value)
    abs(new.value)==0.0 ? delete!(ms,m.id) : ms[m.id]=new
    return ms
end
add!(ms::Elements,mms::Elements)=(for m in mms|>values add!(ms,m) end; ms)

"""
    sub!(ms::Elements) -> typeof(ms)
    sub!(ms::Elements,::Nothing) -> typeof(ms)
    add!(ms::Elements,m) -> typeof(ms)
    sub!(ms::Elements,m::Element) -> typeof(ms)
    sub!(ms::Elements,mms::Elements) -> typeof(ms)

Get the inplace subtraction of elements from a set.
"""
sub!(ms::Elements)=ms
sub!(ms::Elements,::Nothing)=ms
sub!(ms::Elements,m)=add!(ms,convert(scalartype(ms|>valtype),-m))
function sub!(ms::Elements,m::ScalarElement)
    m=convert(scalartype(ms|>valtype),-m)
    old=get(ms,m.id,nothing)
    new=old===nothing ? m : replace(old,value=old.value+m.value)
    abs(new.value)==0.0 ? delete!(ms,m.id) : ms[m.id]=new
    return ms
end
function sub!(ms::Elements,m::Element)
    m=convert(ms|>valtype,m)
    old=get(ms,m.id,nothing)
    new=old==nothing ? -m : replace(old,value=old.value-m.value)
    abs(new.value)==0.0 ? delete!(ms,m.id) : ms[m.id]=new
    return ms
end
sub!(ms::Elements,mms::Elements)=(for m in mms|>values sub!(ms,m) end; ms)

"""
    mul!(ms::Elements,factor::ScalarElement) -> Elements
    mul!(ms::Elements,factor) -> Elements

Get the inplace multiplication of elements with a scalar.
"""
mul!(ms::Elements,factor::ScalarElement)=mul!(ms,factor.value)
function mul!(ms::Elements,factor)
    @assert isa(one(ms|>valtype|>valtype)*factor,ms|>valtype|>valtype) "mul! error: dismatched type, $(ms|>valtype) and $(factor|>typeof)."
    for m in values(ms)
        ms[m.id]=replace(m,value=m.value*factor)
    end
    return ms
end

"""
    div!(ms::Elements,factor::ScalarElement) -> Elements
    div!(ms::Elements,factor) -> Elements

Get the inplace division of element with a scalar.
"""
div!(ms::Elements,factor::ScalarElement)=mul!(ms,1/factor.value)
div!(ms::Elements,factor)=mul!(ms,1/factor)

"""
    +(m::Element) -> typeof(m)
    +(ms::Elements) -> typeof(ms)
    +(m::Element,::Nothing) -> typeof(m)
    +(::Nothing,m::Element) -> typeof(m)
    +(m::Element,factor) -> Elements
    +(factor,m::Element) -> Elements
    +(ms::Elements,::Nothing) -> typeof(ms)
    +(::Nothing,ms::Elements) -> typeof(ms)
    +(ms::Elements,factor) -> Elements
    +(factor,ms::Elements) -> Elements
    +(ms::Elements,m::Element) -> Elements
    +(m1::Element,m2::Element) -> Elements
    +(m::Element,ms::Elements) -> Elements
    +(ms1::Elements,ms2::Elements) -> Elements

Overloaded `+` operator between elements of an algebra over a field.
"""
Base.:+(m::Element)=m
Base.:+(ms::Elements)=ms
Base.:+(m::Element,::Nothing)=m
Base.:+(::Nothing,m::Element)=m
Base.:+(ms::Elements,::Nothing)=ms
Base.:+(::Nothing,ms::Elements)=ms
Base.:+(factor,m::Element)=m+rawelement(m|>typeof)(factor,ID())
Base.:+(m::Element,factor)=m+rawelement(m|>typeof)(factor,ID())
Base.:+(factor,m::ScalarElement)=replace(m,value=m.value+factor)
Base.:+(m::ScalarElement,factor)=replace(m,value=m.value+factor)
Base.:+(factor::ScalarElement,m::Element)=m+factor
Base.:+(m1::ScalarElement,m2::ScalarElement)=replace(m1,value=m1.value+m2.value)
Base.:+(factor,ms::Elements)=ms+rawelement(ms|>valtype)(factor,ID())
Base.:+(ms::Elements,factor)=ms+rawelement(ms|>valtype)(factor,ID())
Base.:+(factor::ScalarElement,ms::Elements)=ms+factor
Base.:+(m::Element,factor::ScalarElement)=(M=promote_type(typeof(m),typeof(factor));add!(Elements{M|>idtype,M}(m.id=>m),factor))
Base.:+(m1::Element,m2::Element)=(M=promote_type(typeof(m1),typeof(m2));add!(Elements{M|>idtype,M}(m1.id=>m1),m2))
Base.:+(m::Element,ms::Elements)=ms+m
Base.:+(ms::Elements,factor::ScalarElement)=(M=promote_type(valtype(ms),typeof(factor));add!(Elements{M|>idtype,M}(ms),factor))
Base.:+(ms::Elements,m::Element)=(M=promote_type(valtype(ms),typeof(m));add!(Elements{M|>idtype,M}(ms),m))
Base.:+(ms1::Elements,ms2::Elements)=(M=promote_type(valtype(ms1),valtype(ms2));add!(Elements{M|>idtype,M}(ms1),ms2))

"""
    *(factor,m::Element) -> Element
    *(m::Element,factor) -> Element
    *(m1::Element,m2::Element) -> Element
    *(m::Element,::Nothing) -> Nothing
    *(::Nothing,m::Element) -> Nothing
    *(factor,ms::Elements) -> Elements
    *(ms::Elements,factor) -> Elements
    *(m::Element,ms::Elements) -> Elements
    *(ms::Elements,m::Element) -> Elements
    *(ms1::Elements,ms2::Elements) -> Elements
    *(ms::Elements,::Nothing) -> Nothing
    *(::Nothing,ms::Elements) -> Nothing

Overloaded `*` operator for element-scalar multiplications and element-element multiplications of an algebra over a field.
"""
Base.:*(m::Element,::Nothing)=nothing
Base.:*(::Nothing,m::Element)=nothing
Base.:*(ms::Elements,::Nothing)=nothing
Base.:*(::Nothing,ms::Elements)=nothing
Base.:*(factor::ScalarElement,m::Element)=m*factor.value
Base.:*(m::Element,factor::ScalarElement)=m*factor.value
Base.:*(m1::ScalarElement,m2::ScalarElement)=replace(m1,value=m1.value*m2.value)
Base.:*(factor,m::Element)=m*factor
Base.:*(m::Element,factor)=replace(m,value=factor*m.value)
Base.:*(factor::ScalarElement,ms::Elements)=ms*factor.value
Base.:*(ms::Elements,factor::ScalarElement)=ms*factor.value
Base.:*(factor,ms::Elements)=ms*factor
Base.:*(ms::Elements,factor)=abs(factor)==0 ? zero(Elements) : Elements(id=>m*factor for (id,m) in ms)
Base.:*(m::Element,ms::Elements)=Elements((m*mm for mm in ms|>values)...)
Base.:*(ms::Elements,m::Element)=Elements((mm*m for mm in ms|>values)...)
Base.:*(ms1::Elements,ms2::Elements)=Elements((m1*m2 for m1 in ms1|>values for m2 in ms2|>values)...)
function Base.:*(m1::Element,m2::Element)
    @assert(    m1|>typeof|>nameof==m2|>typeof|>nameof && m1|>typeof|>fieldcount==m2|>typeof|>fieldcount==2,
                "\"*\" error: not implemented between $(m1|>typeof|>nameof) and $(m2|>typeof|>nameof)."
                )
    typeof(m1).name.wrapper(m1.value*m2.value,m1.id*m2.id)
end

"""
    -(m::Element) -> typeof(m)
    -(ms::Elements) -> typeof(ms)
    -(m::Element,::Nothing) -> typeof(m)
    -(::Nothing,m::Element) -> typeof(m)
    -(ms::Elements,::Nothing) -> typeof(ms)
    -(::Nothing,ms::Elements) -> typeof(ms)
    -(m::Element,factor) -> Elements
    -(factor,m::Element) -> Elements
    -(ms::Elements,factor) -> Elements
    -(factor,ms::Elements) -> Elements
    -(m1::Element,m2::Element) -> Elements
    -(m::Element,ms::Elements) -> Elements
    -(ms::Elements,m::Element) -> Elements
    -(ms1::Elements,ms2::Elements) -> Elements

Overloaded `-` operator between elements of an algebra over a field.
"""
Base.:-(m::Element)=m*(-1)
Base.:-(ms::Elements)=ms*(-1)
Base.:-(m::Element,::Nothing)=m
Base.:-(::Nothing,m::Element)=-m
Base.:-(ms::Elements,::Nothing)=ms
Base.:-(::Nothing,ms::Elements)=-ms
Base.:-(factor,m::Element)=rawelement(m|>typeof)(factor,ID())-m
Base.:-(m::Element,factor)=m+rawelement(m|>typeof)(-factor,ID())
Base.:-(factor,m::ScalarElement)=replace(m,value=factor-m.value)
Base.:-(m::ScalarElement,factor)=replace(m,value=m.value-factor)
Base.:-(m1::ScalarElement,m2::ScalarElement)=replace(m1,value=m1.value-m2.value)
Base.:-(factor,ms::Elements)=rawelement(ms|>valtype)(factor,ID())-ms
Base.:-(ms::Elements,factor)=ms+rawelement(ms|>valtype)(-factor,ID())
Base.:-(factor::ScalarElement,m::Element)=(M=promote_type(typeof(factor),typeof(m));sub!(Elements{M|>idtype,M}(factor.id=>factor),m))
Base.:-(m::Element,factor::ScalarElement)=(M=promote_type(typeof(m),typeof(factor));sub!(Elements{M|>idtype,M}(m.id=>m),factor))
Base.:-(m1::Element,m2::Element)=(M=promote_type(typeof(m1),typeof(m2));sub!(Elements{M|>idtype,M}(m1.id=>m1),m2))
Base.:-(factor::ScalarElement,ms::Elements)=(M=promote_type(typeof(factor),valtype(ms));sub!(Elements{M|>idtype,M}(factor.id=>factor),ms))
Base.:-(ms::Elements,factor::ScalarElement)=(M=promote_type(valtype(ms),typeof(factor));sub!(Elements{M|>idtype,M}(ms),factor))
Base.:-(m::Element,ms::Elements)=(M=promote_type(typeof(m),valtype(ms));sub!(Elements{M|>idtype,M}(m.id=>m),ms))
Base.:-(ms::Elements,m::Element)=(M=promote_type(valtype(ms),typeof(m));sub!(Elements{M|>idtype,M}(ms),m))
Base.:-(ms1::Elements,ms2::Elements)=(M=promote_type(valtype(ms1),valtype(ms2));sub!(Elements{M|>idtype,M}(ms1),ms2))

"""
    /(m::Element,factor) -> Element
    /(m::Element,factor::ScalarElement) -> Element
    /(ms::Elements,factor) -> Elements
    /(ms::Elements,factor::ScalarElement) -> Elements

Overloaded `/` operator for element-scalar division of an algebra over a field.
"""
Base.:/(m::Element,factor)=m*(1/factor)
Base.:/(m::Element,factor::ScalarElement)=m*(1/factor.value)
Base.:/(ms::Elements,factor)=ms*(1/factor)
Base.:/(ms::Elements,factor::ScalarElement)=ms*(1/factor.value)

"""
    ^(m::Element,n::Int) -> Element
    ^(ms::Elements,n::Int) -> Elements

Overloaded `^` operator for element-integer power of an algebra over a field.
"""
Base.:^(m::Element,n::Int)=(@assert n>0 "^ error: non-positive integers are not allowed."; prod(ntuple(i->m,n)))
Base.:^(ms::Elements,n::Int)=(@assert n>0 "^ error: non-positive integers are not allowed."; prod(ntuple(i->ms,n)))

"""
    ⊗(m::Element,ms::Elements) -> Elements
    ⊗(ms::Elements,m::Element) -> Elements
    ⊗(ms1::Elements,ms2::Elements) -> Elements

Overloaded `⊗` operator for element-element multiplications of an algebra over a field.
"""
⊗(m::Element,ms::Elements)=Elements((m⊗mm for mm in ms|>values)...)
⊗(ms::Elements,m::Element)=Elements((mm⊗m for mm in ms|>values)...)
⊗(ms1::Elements,ms2::Elements)=Elements((m1⊗m2 for m1 in ms1|>values for m2 in ms2|>values)...)

"""
    ⋅(m::Element,ms::Elements) -> Elements
    ⋅(ms::Elements,m::Element) -> Elements
    ⋅(ms1::Elements,ms2::Elements) -> Elements

Overloaded `⋅` operator for element-element multiplications of an algebra over a field.
"""
⋅(m::Element,ms::Elements)=Elements((m⋅mm for mm in ms|>values)...)
⋅(ms::Elements,m::Element)=Elements((mm⋅m for mm in ms|>values)...)
⋅(ms1::Elements,ms2::Elements)=Elements((m1⋅m2 for m1 in ms1|>values for m2 in ms2|>values)...)

"""
    split(m::Element) -> Tuple{Any,Vararg{Element}}

Split an element into the coefficient and a sequence of rank-1 elements.
"""
@generated function Base.split(m::Element)
    @assert m|>fieldnames==(:value,:id) "split error: not supported split of $(nameof(typeof(m)))."
    exprs=[:(m.value)]
    for i=1:rank(m)
        push!(exprs,:(typeof(m).name.wrapper(one(m|>valtype),ID(m.id[$i]))))
    end
    return Expr(:tuple,exprs...)
end

"""
    replace(m::Element,pairs::Pair{<:SimpleID,<:Union{Element,Elements}}...) -> Element/Elements
    replace(ms::Elements,pairs::Pair{<:SimpleID,<:Union{Element,Elements}}...) -> Elements

Replace the rank-1 components of an element with new element/elements.
"""
function Base.replace(m::Element,pairs::Pair{<:SimpleID,<:Union{Element,Elements}}...)
    @assert m|>typeof|>fieldnames==(:value,:id) "replace error: not supported replacement of $(nameof(typeof(m)))."
    replacedids=NTuple{length(pairs),idtype(m)|>eltype}(pair.first for pair in pairs)
    ms=split(m)
    result=ms[1]
    for i=1:rank(m)
        index=findfirst(isequal(m.id[i]),replacedids)
        result=result*(isa(index,Int) ? pairs[index].second : ms[i+1])
    end
    return result
end
function Base.replace(ms::Elements,pairs::Pair{<:SimpleID,<:Union{Element,Elements}}...)
    result=elementstype(pairs...)()
    for m in values(ms)
        add!(result,replace(m,pairs...))
    end
    return result
end
@generated function elementstype(ms::Vararg{Pair{<:SimpleID,<:Union{Element,Elements}},N}) where N
    ms=ntuple(i->(fieldtype(ms[i],2)<:Elements) ? fieldtype(ms[i],2)|>valtype : fieldtype(ms[i],2),Val(N))
    @assert mapreduce(m->(m|>fieldnames)==(:value,:id),&,ms) "elementscommontype error: not supported."
    val=mapreduce(valtype,promote_type,ms)
    name=reduce(typejoin,ms)|>rawelement
    return isconcretetype(val) ? Elements{ID,name{val}} : Elements{ID,name{<:val}}
end

"""
    sequence(m::Element,table=nothing) -> NTuple{rank(m),Int}

Get the sequence of the ids of an element according to a table.
"""
@generated sequence(m::Element,table)=Expr(:tuple,[:(get(table,m.id[$i],nothing)) for i=1:rank(m)]...)

"""
    permute!(result::Elements,m::Element,table=nothing) -> Elements
    permute!(result::Elements,ms::Elements,table=nothing) -> Elements

Permute the ids of an-element/a-set-of-elements to the descending order according to a table, and store the permuted elements in result.
"""
function Base.permute!(result::Elements,m::Element,table=nothing)
    cache=valtype(result)[m]
    while length(cache)>0
        current=pop!(cache)
        pos=elementcommuteposition(sequence(current,table))
        if isa(pos,Nothing)
            add!(result,current)
        else
            left,right=elementleft(current,pos),elementright(current,pos)
            for middle in permute(typeof(current),current.id[pos],current.id[pos+1],table)
                temp=left*middle*right
                temp===nothing || push!(cache,temp)
            end
        end
    end
    return result
end
function Base.permute!(result::Elements,ms::Elements,table=nothing)
    for m in values(ms)
        permute!(result,m,table)
    end
    return result
end
function elementcommuteposition(seqs)
    pos=1
    while pos<length(seqs)
        seqs[pos]<seqs[pos+1] && return pos
        pos+=1
    end
    return nothing
end
elementleft(m::Element,i::Int)=typeof(m).name.wrapper(m.value,m.id[1:i-1])
elementright(m::Element,i::Int)=typeof(m).name.wrapper(one(m.value),m.id[i+2:end])

"""
    permute(m::Element,table=nothing) -> Elements
    permute(ms::Elements,table=nothing) -> Elements

Permute the ids of an-element/a-set-of-elements to the descending order according to a table.
"""
function permute(m::Element,table=nothing)
    result=Elements{ID,rawelement(m|>typeof){valtype(m),<:ID}}()
    permute!(result,m,table)
end
function permute(ms::Elements,table=nothing)
    result=Elements{ID,rawelement(ms|>valtype){valtype(ms|>valtype),<:ID}}()
    permute!(result,ms,table)
end

end #module
