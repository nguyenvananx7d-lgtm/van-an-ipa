using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

namespace ProjectEspPatch
{
    internal static class WeaveEsp
    {
        private static AssemblyDefinition targetAssembly;
        private static ModuleDefinition targetModule;
        private static MethodDefinition helperMethod;
        private static MethodDefinition targetMethod;
        private static readonly Dictionary<VariableDefinition, VariableDefinition> Variables
            = new Dictionary<VariableDefinition, VariableDefinition>();
        private static readonly Dictionary<Instruction, Instruction> Instructions
            = new Dictionary<Instruction, Instruction>();

        private static IEnumerable<TypeDefinition> AllTypes(ModuleDefinition module)
        {
            Stack<TypeDefinition> pending = new Stack<TypeDefinition>(module.Types.Reverse());
            while (pending.Count != 0)
            {
                TypeDefinition type = pending.Pop();
                yield return type;
                for (int index = type.NestedTypes.Count - 1; index >= 0; index--)
                {
                    pending.Push(type.NestedTypes[index]);
                }
            }
        }

        private static TypeDefinition RequireType(ModuleDefinition module, string fullName)
        {
            string cecilName = fullName.Replace('+', '/');
            TypeDefinition type = AllTypes(module).SingleOrDefault(value =>
                value.FullName == cecilName);
            if (type == null)
            {
                throw new InvalidOperationException("Target type was not found: " + fullName);
            }
            return type;
        }

        private sealed class MemberBinding
        {
            public string DeclaringType;
            public string OldName;
            public string NewName;
        }

        private sealed class BindingMap
        {
            public readonly Dictionary<string, string> Types
                = new Dictionary<string, string>();
            public readonly List<MemberBinding> Fields = new List<MemberBinding>();
            public readonly List<MemberBinding> Methods = new List<MemberBinding>();

            public string TypeName(string oldName)
            {
                string value;
                if (!Types.TryGetValue(oldName, out value))
                {
                    throw new InvalidOperationException("Missing type binding: " + oldName);
                }
                return value;
            }

            public string FieldName(string declaringType, string oldName)
            {
                return Fields.Single(value => value.DeclaringType == declaringType
                    && value.OldName == oldName).NewName;
            }
        }

        private static BindingMap LoadBindings(string path)
        {
            BindingMap result = new BindingMap();
            foreach (string rawLine in File.ReadAllLines(path))
            {
                string line = rawLine.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                string[] parts = line.Split('\t');
                if (parts[0] == "TYPE" && parts.Length == 3)
                {
                    result.Types.Add(parts[1], parts[2]);
                }
                else if ((parts[0] == "FIELD" || parts[0] == "METHOD")
                    && parts.Length == 4)
                {
                    MemberBinding binding = new MemberBinding {
                        DeclaringType = parts[1], OldName = parts[2], NewName = parts[3]
                    };
                    (parts[0] == "FIELD" ? result.Fields : result.Methods).Add(binding);
                }
                else
                {
                    throw new InvalidOperationException("Invalid binding line: " + rawLine);
                }
            }
            return result;
        }

        private static void RenameField(TypeDefinition type, string oldName, string newName)
        {
            FieldDefinition field = type.Fields.Single(value => value.Name == oldName);
            field.Name = newName;
        }

        private static void RenameMethod(TypeDefinition type, string oldName, string newName)
        {
            MethodDefinition method = type.Methods.Single(value =>
                value.Name == oldName && value.Parameters.Count == 0);
            method.Name = newName;
        }

        private static void RenameType(TypeDefinition type, string newFullName)
        {
            string cecilName = newFullName.Replace('+', '/');
            int separator = Math.Max(cecilName.LastIndexOf('/'), cecilName.LastIndexOf('.'));
            string newName = separator < 0 ? cecilName : cecilName.Substring(separator + 1);
            string newContainer = separator < 0 ? "" : cecilName.Substring(0, separator);
            string oldFullName = type.FullName;
            int oldSeparator = Math.Max(oldFullName.LastIndexOf('/'), oldFullName.LastIndexOf('.'));
            string oldContainer = oldSeparator < 0 ? "" : oldFullName.Substring(0, oldSeparator);
            if (newContainer != oldContainer)
            {
                throw new InvalidOperationException(
                    "Retargeting cannot move a type: " + oldFullName + " -> " + newFullName);
            }
            type.Name = newName;
        }

        private static string SimpleIdentifier(string fullName)
        {
            string value = fullName.Replace('+', '.').Replace('/', '.');
            return value.Substring(value.LastIndexOf('.') + 1);
        }

        private static void WriteAdaptedTarget(string input, string output, string bindingPath)
        {
            DefaultAssemblyResolver resolver = new DefaultAssemblyResolver();
            resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(input)));
            AssemblyDefinition assembly = AssemblyDefinition.ReadAssembly(
                input, new ReaderParameters { AssemblyResolver = resolver });
            ModuleDefinition module = assembly.MainModule;
            BindingMap bindings = LoadBindings(bindingPath);
            foreach (MemberBinding binding in bindings.Fields)
            {
                RenameField(RequireType(module, binding.DeclaringType),
                    binding.OldName, binding.NewName);
            }
            foreach (MemberBinding binding in bindings.Methods)
            {
                RenameMethod(RequireType(module, binding.DeclaringType),
                    binding.OldName, binding.NewName);
            }

            List<KeyValuePair<string, string>> identifierMap = bindings.Types
                .Select(value => new KeyValuePair<string, string>(
                    SimpleIdentifier(value.Key), SimpleIdentifier(value.Value)))
                .Concat(bindings.Methods.Select(value =>
                    new KeyValuePair<string, string>(value.OldName, value.NewName)))
                .ToList();
            foreach (TypeDefinition type in AllTypes(module).Where(value =>
                value.Namespace == "IFix" && value.Name.StartsWith("IDMAP")))
            {
                foreach (FieldDefinition field in type.Fields)
                {
                    foreach (KeyValuePair<string, string> pair in identifierMap)
                    {
                        field.Name = field.Name.Replace(pair.Key, pair.Value);
                    }
                }
            }
            foreach (KeyValuePair<string, string> binding in bindings.Types)
            {
                RenameType(RequireType(module, binding.Key), binding.Value);
            }

            assembly.Write(output);
            Console.WriteLine("adapted=" + output);
        }

        private static TypeReference MapType(TypeReference type)
        {
            if (type is ByReferenceType)
            {
                return new ByReferenceType(MapType(((ByReferenceType)type).ElementType));
            }
            if (type is PointerType)
            {
                return new PointerType(MapType(((PointerType)type).ElementType));
            }
            if (type is ArrayType)
            {
                ArrayType array = (ArrayType)type;
                return new ArrayType(MapType(array.ElementType), array.Rank);
            }
            if (type is GenericInstanceType)
            {
                GenericInstanceType source = (GenericInstanceType)type;
                GenericInstanceType mapped = new GenericInstanceType(MapType(source.ElementType));
                foreach (TypeReference argument in source.GenericArguments)
                {
                    mapped.GenericArguments.Add(MapType(argument));
                }
                return mapped;
            }

            if (type.Scope != null && type.Scope.Name == targetAssembly.Name.Name)
            {
                TypeDefinition local = targetModule.GetType(type.FullName);
                if (local == null)
                {
                    throw new InvalidOperationException("Target type was not found: " + type.FullName);
                }
                return local;
            }
            return targetModule.ImportReference(type);
        }

        private static bool SameType(TypeReference left, TypeReference right)
        {
            return MapType(left).FullName == right.FullName;
        }

        private static MethodReference MapMethod(MethodReference method)
        {
            GenericInstanceMethod generic = method as GenericInstanceMethod;
            if (generic != null)
            {
                GenericInstanceMethod mapped = new GenericInstanceMethod(
                    MapMethod(generic.ElementMethod));
                foreach (TypeReference argument in generic.GenericArguments)
                {
                    mapped.GenericArguments.Add(MapType(argument));
                }
                return mapped;
            }

            TypeReference declaringType = MapType(method.DeclaringType);
            TypeDefinition localType = declaringType as TypeDefinition;
            if (localType != null && localType.Module == targetModule)
            {
                string targetName = method.Name;
                if (localType.FullName == "COW.GamePlay.Player"
                    && targetName == "EspBaseIsMovableEntity")
                {
                    targetName = "<>iFixBaseProxy_get_IsMovableEntity";
                }
                else if (localType.FullName == "COW.GamePlay.PlayerNetwork"
                    && targetName == "EspBaseOnUpdate")
                {
                    targetName = "<>iFixBaseProxy_OnUpdate";
                }
                List<MethodDefinition> matches = localType.Methods.Where(candidate =>
                    candidate.Name == targetName
                    && candidate.Parameters.Count == method.Parameters.Count
                    && candidate.GenericParameters.Count == method.GenericParameters.Count
                    && SameType(method.ReturnType, candidate.ReturnType)
                    && candidate.Parameters.Select(parameter => parameter.ParameterType.FullName)
                        .SequenceEqual(method.Parameters.Select(parameter => MapType(parameter.ParameterType).FullName)))
                    .ToList();
                if (matches.Count != 1)
                {
                    throw new InvalidOperationException(
                        "Expected one target method for " + method.FullName + ", found " + matches.Count);
                }
                return matches[0];
            }
            return targetModule.ImportReference(method);
        }

        private static FieldReference MapField(FieldReference field)
        {
            TypeReference declaringType = MapType(field.DeclaringType);
            TypeDefinition localType = declaringType as TypeDefinition;
            if (localType != null && localType.Module == targetModule)
            {
                FieldDefinition match = localType.Fields.SingleOrDefault(candidate =>
                    candidate.Name == field.Name && SameType(field.FieldType, candidate.FieldType));
                if (match == null)
                {
                    throw new InvalidOperationException("Target field was not found: " + field.FullName);
                }
                return match;
            }
            return targetModule.ImportReference(field);
        }

        private static object MapOperand(Instruction source)
        {
            object operand = source.Operand;
            if (operand == null || operand is string || operand is byte || operand is sbyte
                || operand is int || operand is long || operand is float || operand is double)
            {
                return operand;
            }
            if (operand is VariableDefinition)
            {
                return Variables[(VariableDefinition)operand];
            }
            if (operand is ParameterDefinition)
            {
                ParameterDefinition parameter = (ParameterDefinition)operand;
                if (parameter == helperMethod.Parameters[0])
                {
                    return targetMethod;
                }
                throw new InvalidOperationException("Unexpected helper parameter operand");
            }
            if (operand is MethodReference)
            {
                return MapMethod((MethodReference)operand);
            }
            if (operand is FieldReference)
            {
                return MapField((FieldReference)operand);
            }
            if (operand is TypeReference)
            {
                return MapType((TypeReference)operand);
            }
            if (operand is Instruction)
            {
                return Instructions[(Instruction)operand];
            }
            if (operand is Instruction[])
            {
                return ((Instruction[])operand).Select(value => Instructions[value]).ToArray();
            }
            throw new InvalidOperationException("Unsupported IL operand: " + operand.GetType().FullName);
        }

        private static Instruction CloneInstruction(Instruction source)
        {
            ParameterDefinition helperParameter = source.Operand as ParameterDefinition;
            if (helperParameter != null)
            {
                int helperIndex = helperMethod.Parameters.IndexOf(helperParameter);
                if (source.OpCode != OpCodes.Ldarg && source.OpCode != OpCodes.Ldarg_S)
                {
                    throw new InvalidOperationException(
                        "Unsupported access to helper parameter: " + source.OpCode);
                }
                if (helperIndex == 0)
                {
                    return Instruction.Create(OpCodes.Ldarg_0);
                }
                int targetIndex = helperIndex - 1;
                if (targetIndex < 0 || targetIndex >= targetMethod.Parameters.Count
                    || !SameType(helperParameter.ParameterType,
                        targetMethod.Parameters[targetIndex].ParameterType))
                {
                    throw new InvalidOperationException(
                        "Helper parameter does not match target method: "
                        + helperParameter.Name);
                }
                return Instruction.Create(source.OpCode, targetMethod.Parameters[targetIndex]);
            }

            object operand = MapOperand(source);
            if (operand == null) return Instruction.Create(source.OpCode);
            if (operand is sbyte) return Instruction.Create(source.OpCode, (sbyte)operand);
            if (operand is byte) return Instruction.Create(source.OpCode, (byte)operand);
            if (operand is int) return Instruction.Create(source.OpCode, (int)operand);
            if (operand is long) return Instruction.Create(source.OpCode, (long)operand);
            if (operand is float) return Instruction.Create(source.OpCode, (float)operand);
            if (operand is double) return Instruction.Create(source.OpCode, (double)operand);
            if (operand is string) return Instruction.Create(source.OpCode, (string)operand);
            if (operand is VariableDefinition)
                return Instruction.Create(source.OpCode, (VariableDefinition)operand);
            if (operand is MethodReference)
                return Instruction.Create(source.OpCode, (MethodReference)operand);
            if (operand is FieldReference)
                return Instruction.Create(source.OpCode, (FieldReference)operand);
            if (operand is TypeReference)
                return Instruction.Create(source.OpCode, (TypeReference)operand);
            if (operand is Instruction)
                return Instruction.Create(source.OpCode, (Instruction)operand);
            if (operand is Instruction[])
                return Instruction.Create(source.OpCode, (Instruction[])operand);
            throw new InvalidOperationException("Unsupported mapped operand: " + operand.GetType().FullName);
        }

        private static void CloneBody()
        {
            MethodBody body = new MethodBody(targetMethod);
            body.InitLocals = helperMethod.Body.InitLocals;
            body.MaxStackSize = helperMethod.Body.MaxStackSize;
            targetMethod.Body = body;

            Variables.Clear();
            foreach (VariableDefinition source in helperMethod.Body.Variables)
            {
                VariableDefinition mapped = new VariableDefinition(MapType(source.VariableType));
                Variables.Add(source, mapped);
                body.Variables.Add(mapped);
            }

            Instructions.Clear();
            foreach (Instruction source in helperMethod.Body.Instructions)
            {
                Instruction shell = Instruction.Create(OpCodes.Nop);
                Instructions.Add(source, shell);
                body.Instructions.Add(shell);
            }
            for (int index = 0; index < helperMethod.Body.Instructions.Count; index++)
            {
                Instruction source = helperMethod.Body.Instructions[index];
                body.Instructions[index] = CloneInstruction(source);
                Instructions[source] = body.Instructions[index];
            }

            // Branch operands were cloned before every destination had its final object.
            foreach (Instruction source in helperMethod.Body.Instructions)
            {
                Instruction destination = Instructions[source];
                if (source.Operand is Instruction)
                {
                    destination.Operand = Instructions[(Instruction)source.Operand];
                }
                else if (source.Operand is Instruction[])
                {
                    destination.Operand = ((Instruction[])source.Operand)
                        .Select(value => Instructions[value]).ToArray();
                }
            }

            foreach (ExceptionHandler source in helperMethod.Body.ExceptionHandlers)
            {
                body.ExceptionHandlers.Add(new ExceptionHandler(source.HandlerType)
                {
                    CatchType = source.CatchType == null ? null : MapType(source.CatchType),
                    TryStart = Instructions[source.TryStart],
                    TryEnd = source.TryEnd == null ? null : Instructions[source.TryEnd],
                    HandlerStart = Instructions[source.HandlerStart],
                    HandlerEnd = source.HandlerEnd == null ? null : Instructions[source.HandlerEnd],
                    FilterStart = source.FilterStart == null ? null : Instructions[source.FilterStart],
                });
            }
        }

        private static void WritePublicReference(
            string input, string output, string searchDirectory, string bindingPath)
        {
            DefaultAssemblyResolver resolver = new DefaultAssemblyResolver();
            resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(input)));
            resolver.AddSearchDirectory(Path.GetFullPath(searchDirectory));
            AssemblyDefinition assembly = AssemblyDefinition.ReadAssembly(
                input, new ReaderParameters { AssemblyResolver = resolver });
            ModuleDefinition module = assembly.MainModule;
            BindingMap bindings = LoadBindings(bindingPath);
            foreach (string name in new[] {
                "COW.GamePlay.Player",
                "COW.GamePlay.PlayerNetwork",
                "COW.GamePlay.AttackableEntity",
                "COW.GameFacade",
                bindings.TypeName("COW.GamePlay.EMKJHAJNPDH"),
                "COW.GamePlay.SceneEditBoxSelectTool",
                bindings.TypeName("COW.GamePlay.GMPGMPFNMFP"),
                bindings.TypeName("COW.GamePlay.JKCLPFEFMNG"),
                "COW.GamePlay.PlayerAttributes"
            })
            {
                TypeDefinition type = RequireType(module, name);
                type.Attributes = (type.Attributes & ~TypeAttributes.VisibilityMask)
                    | TypeAttributes.Public;
            }

            TypeDefinition player = module.GetType("COW.GamePlay.Player");
            foreach (string name in new[] {
                "RootTransform", "CurHP", "MaxHP", "NickName", "IsDieing",
                "AimStartPostion", "HeadCollider", "NeckBone", "FireColliders",
                "Attributes", "IsSkyDiving", "IsSkySurfing", "IsParachuting",
                "CharacterController"
            })
            {
                if (player.Properties.Any(property => property.Name == name)) continue;
                MethodDefinition getter = player.Methods.Single(method =>
                    method.Name == "get_" + name && method.Parameters.Count == 0);
                player.Properties.Add(new PropertyDefinition(
                    name, PropertyAttributes.None, getter.ReturnType) { GetMethod = getter });
            }
            TypeDefinition sceneTool = module.GetType("COW.GamePlay.SceneEditBoxSelectTool");
            foreach (string name in new[] {
                bindings.FieldName("COW.GamePlay.SceneEditBoxSelectTool", "DKNELPFOCHG"),
                bindings.FieldName("COW.GamePlay.SceneEditBoxSelectTool", "FMMMAPKGAAJ"),
                bindings.FieldName("COW.GamePlay.SceneEditBoxSelectTool", "EEKIAPPAGCL")
            })
            {
                FieldDefinition field = sceneTool.Fields.Single(value => value.Name == name);
                field.Attributes = (field.Attributes & ~FieldAttributes.FieldAccessMask)
                    | FieldAttributes.Public;
            }

            assembly.Write(output);
            Console.WriteLine("reference=" + output);
        }

        private static int Main(string[] args)
        {
            if (args.Length == 4 && args[0] == "--adapt-target")
            {
                WriteAdaptedTarget(args[1], args[2], args[3]);
                return 0;
            }
            if (args.Length == 5 && args[0] == "--public-reference")
            {
                WritePublicReference(args[1], args[2], args[3], args[4]);
                return 0;
            }
            if (args.Length != 4)
            {
                Console.Error.WriteLine(
                    "usage: WeaveEsp TARGET_DLL ESP_LOGIC_DLL OUTPUT_DLL SEARCH_DIRECTORY");
                Console.Error.WriteLine(
                    "   or: WeaveEsp --adapt-target OLD_DLL OUTPUT_DLL BINDINGS_TSV");
                Console.Error.WriteLine(
                    "   or: WeaveEsp --public-reference TARGET_DLL OUTPUT_DLL "
                    + "SEARCH_DIRECTORY BINDINGS_TSV");
                return 2;
            }

            DefaultAssemblyResolver resolver = new DefaultAssemblyResolver();
            resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(args[0])));
            resolver.AddSearchDirectory(Path.GetDirectoryName(Path.GetFullPath(args[1])));
            resolver.AddSearchDirectory(Path.GetFullPath(args[3]));
            ReaderParameters parameters = new ReaderParameters { AssemblyResolver = resolver };
            targetAssembly = AssemblyDefinition.ReadAssembly(args[0], parameters);
            AssemblyDefinition helperAssembly = AssemblyDefinition.ReadAssembly(args[1], parameters);
            targetModule = targetAssembly.MainModule;

            TypeDefinition player = targetModule.GetType("COW.GamePlay.Player");
            TypeDefinition sceneTool = targetModule.GetType("COW.GamePlay.SceneEditBoxSelectTool");
            TypeDefinition helperType = helperAssembly.MainModule.GetType("ProjectEspPatch.Logic");

            targetMethod = player.Methods.Single(method =>
                method.Name == "IsReallyInStealth" && method.Parameters.Count == 0);
            helperMethod = helperType.Methods.Single(method => method.Name == "Bootstrap");

            foreach (TypeDefinition type in targetModule.Types
                .Where(type => type.Namespace == "IFix").ToList())
            {
                targetModule.Types.Remove(type);
            }
            CloneBody();

            int bootstrapInstructions = targetMethod.Body.Instructions.Count;
            targetMethod = sceneTool.Methods.Single(method =>
                method.Name == "OnGUI" && method.Parameters.Count == 0);
            helperMethod = helperType.Methods.Single(method => method.Name == "Draw");
            CloneBody();
            int drawInstructions = targetMethod.Body.Instructions.Count;

            targetAssembly.Write(args[2]);

            Console.WriteLine("woven=" + args[2]);
            Console.WriteLine("bootstrap_instructions=" + bootstrapInstructions);
            Console.WriteLine("draw_instructions=" + drawInstructions);
            return 0;
        }
    }
}
