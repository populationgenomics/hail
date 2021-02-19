#include <hail/query/backend/compile.hpp>
#include <hail/query/backend/svalue.hpp>
#include <llvm/IR/Verifier.h>
#include <llvm/Support/raw_ostream.h>

namespace hail {

CompileModule::CompileModule(TypeContext &tc,
			     Module *module,
			     const std::vector<EmitType> &param_types,
			     EmitType return_type,
			     llvm::LLVMContext &llvm_context,
			     llvm::Module *llvm_module)
  : tc(tc),
    llvm_context(llvm_context),
    llvm_module(llvm_module) {
  auto main = module->get_function("main");
  // FIXME
  assert(main);

  CompileFunction(tc, main, param_types, return_type, llvm_context, llvm_module);
}

CompileFunction::CompileFunction(TypeContext &tc,
				 Function *function,
				 const std::vector<EmitType> &param_types,
				 EmitType return_type,
				 llvm::LLVMContext &llvm_context,
				 llvm::Module *llvm_module)
  : tc(tc),
    function(function),
    param_types(param_types),
    return_type(return_type),
    llvm_context(llvm_context),
    llvm_ir_builder(llvm_context),
    llvm_module(llvm_module),
    ir_type(tc, function) {
  auto llvm_ft = llvm::FunctionType::get(llvm::Type::getVoidTy(llvm_context),
					 {llvm::Type::getInt8PtrTy(llvm_context),
					  llvm::Type::getInt8PtrTy(llvm_context)},
					 false);
  llvm_function = llvm::Function::Create(llvm_ft,
					 llvm::Function::ExternalLinkage,
					 "__hail_f",
					 llvm_module);

  auto entry = llvm::BasicBlock::Create(llvm_context, "entry", llvm_function);
  llvm_ir_builder.SetInsertPoint(entry);

  auto result = emit(function->get_body()).as_data(*this);
  std::vector<llvm::Value *> result_llvm_values;
  result.get_constituent_values(result_llvm_values);
  assert(result_llvm_values.size() == 2);

  auto return_address = llvm_function->getArg(0);
  llvm_ir_builder.CreateStore(result_llvm_values[0], return_address);

  llvm::Value *value_address = llvm_ir_builder.CreateGEP(return_address,
							 llvm::ConstantInt::get(llvm_context, llvm::APInt(64, 8)));
  value_address = llvm_ir_builder.CreateBitCast(value_address,
						llvm::PointerType::get(result_llvm_values[1]->getType(), 0));
  llvm_ir_builder.CreateStore(result_llvm_values[1], value_address);
  llvm_ir_builder.CreateRetVoid();

  verifyFunction(*llvm_function, &llvm::errs());

  llvm_function->print(llvm::errs(), nullptr);
}

llvm::Type *
CompileFunction::get_llvm_type(PrimitiveType pt) const {
  switch (pt) {
  case PrimitiveType::VOID:
    return llvm::Type::getVoidTy(llvm_context);
  case PrimitiveType::INT8:
    return llvm::Type::getInt8Ty(llvm_context);
  case PrimitiveType::INT32:
    return llvm::Type::getInt32Ty(llvm_context);
  case PrimitiveType::INT64:
    return llvm::Type::getInt64Ty(llvm_context);
  case PrimitiveType::FLOAT32:
    return llvm::Type::getFloatTy(llvm_context);
  case PrimitiveType::FLOAT64:
    return llvm::Type::getDoubleTy(llvm_context);
  case PrimitiveType::POINTER:
    return llvm::Type::getInt8PtrTy(llvm_context);
  default:
    abort();
  }
}

llvm::AllocaInst *
CompileFunction::make_entry_alloca(llvm::Type *llvm_type) {
  llvm::IRBuilder<> builder(&llvm_function->getEntryBlock(),
			    llvm_function->getEntryBlock().begin());
  return builder.CreateAlloca(llvm_type);
}

EmitValue
CompileFunction::emit(Block *x) {
  assert(x->get_children().size() == 1);
  return emit(x->get_child(0));
}

EmitValue
CompileFunction::emit(Input *x) {
  if (x->get_parent()->get_function_parent()) {
    auto param_type = param_types[x->index];
    std::vector<PrimitiveType> constituent_types;
    param_type.get_constituent_types(constituent_types);
    assert(constituent_types.size() == 2);
    assert(constituent_types[0] == PrimitiveType::INT8);

    auto params_address = llvm_function->getArg(1);
    auto param_address = llvm_ir_builder.CreateGEP(params_address,
						   {llvm::ConstantInt::get(llvm_context, llvm::APInt(64, x->index * 16))});
    auto m = llvm_ir_builder.CreateLoad(get_llvm_type(constituent_types[0]),
					param_address);
    llvm::Type *value_llvm_type = get_llvm_type(constituent_types[1]);
    llvm::Value *value_address = llvm_ir_builder.CreateGEP(param_address,
						     {llvm::ConstantInt::get(llvm_context, llvm::APInt(64, 8))});
    value_address = llvm_ir_builder.CreateBitCast(value_address,
						  llvm::PointerType::get(value_llvm_type, 0));
    auto llvm_value = llvm_ir_builder.CreateLoad(value_llvm_type, value_address);

    std::vector<llvm::Value *> param_llvm_values{m, llvm_value};
    return param_type.from_llvm_values(param_llvm_values, 0);
  }

  abort();
}

const SType *
CompileFunction::get_default_stype(const Type *t) {
  switch (t->tag) {
  case Type::Tag::BOOL:
    return new SBool(t);
  case Type::Tag::INT32:
    return new SInt32(t);
  case Type::Tag::INT64:
    return new SInt64(t);
  case Type::Tag::FLOAT32:
    return new SFloat32(t);
  case Type::Tag::FLOAT64:
    return new SFloat64(t);
  default:
    abort();
  }
}

EmitValue
CompileFunction::emit(Literal *x) {
  auto t = ir_type(x);

  if (x->value.get_missing())
    return EmitType(get_default_stype(t)).make_na(*this);

  switch (ir_type(x)->tag) {
  case Type::Tag::BOOL:
    {
      auto m = llvm::ConstantInt::get(llvm::Type::getInt8Ty(llvm_context), 0);
      auto c = llvm::ConstantInt::get(llvm_context, llvm::APInt(1, x->value.as_bool()));
      return EmitValue(m, new SBoolValue(new SBool(t), c));
    }
  case Type::Tag::INT32:
    {
      auto m = llvm::ConstantInt::get(llvm::Type::getInt8Ty(llvm_context), 0);
      auto c = llvm::ConstantInt::get(llvm_context, llvm::APInt(32, x->value.as_int32()));
      return EmitValue(m, new SInt32Value(new SInt32(t), c));
    }
  case Type::Tag::INT64:
    {
      auto m = llvm::ConstantInt::get(llvm::Type::getInt8Ty(llvm_context), 0);
      auto c = llvm::ConstantInt::get(llvm_context, llvm::APInt(64, x->value.as_int64()));
      return EmitValue(m, new SInt64Value(new SInt32(t), c));
    }
  case Type::Tag::FLOAT32:
    {
      auto m = llvm::ConstantInt::get(llvm::Type::getInt8Ty(llvm_context), 0);
      auto c = llvm::ConstantFP::get(llvm_context, llvm::APFloat(x->value.as_float32()));
      return EmitValue(m, new SFloat32Value(new SFloat32(t), c));
    }
  case Type::Tag::FLOAT64:
    {
  auto m = llvm::ConstantInt::get(llvm::Type::getInt8Ty(llvm_context), 0);
      auto c = llvm::ConstantFP::get(llvm_context, llvm::APFloat(x->value.as_float64()));
      return EmitValue(m, new SFloat64Value(new SFloat64(t), c));
    }
  default:
    abort();
  }
}

EmitValue
CompileFunction::emit(NA *x) {
  return EmitType(get_default_stype(x->type)).make_na(*this);
}

EmitValue
CompileFunction::emit(IsNA *x) {
  auto cond = emit(x->get_child(0)).as_control(*this);

  llvm::AllocaInst *l = make_entry_alloca(llvm::Type::getInt8Ty(llvm_context));

  auto merge_bb = llvm::BasicBlock::Create(llvm_context, "isna_merge", llvm_function);
  llvm_ir_builder.SetInsertPoint(cond.missing_block);
  llvm_ir_builder.CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(llvm_context), 1), l);
  llvm_ir_builder.CreateBr(merge_bb);

  llvm_ir_builder.SetInsertPoint(cond.present_block);
  llvm_ir_builder.CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(llvm_context), 0), l);
  llvm_ir_builder.CreateBr(merge_bb);

  llvm_ir_builder.SetInsertPoint(merge_bb);
  llvm::Value *v = llvm_ir_builder.CreateLoad(l);

  auto m = llvm::ConstantInt::get(llvm::Type::getInt8Ty(llvm_context), 0);
  return EmitValue(m, new SBoolValue(new SBool(ir_type(x)), v));
}

EmitValue
CompileFunction::emit(IR *x) {
  return x->dispatch([this](auto x) {
		       return emit(x);
		     });
}

}
