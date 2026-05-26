/*
 * Copyright 2024 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.gradle.internal.serialize.codecs.core

import org.gradle.internal.configuration.problems.DocumentationSection
import org.gradle.internal.serialize.graph.Codec
import org.gradle.internal.serialize.graph.IsolateContext
import org.gradle.internal.serialize.graph.ReadContext
import org.gradle.internal.serialize.graph.WriteContext
import org.gradle.internal.serialize.graph.codecs.findCodecThatWidensIncompatibly
import org.gradle.internal.serialize.graph.encodeBean
import org.gradle.internal.serialize.graph.decodeBean
import org.gradle.internal.serialize.graph.logUnsupported
import org.objectweb.asm.Type
import org.objectweb.asm.Type.getArgumentTypes
import java.lang.invoke.SerializedLambda
import kotlin.reflect.KClass


/**
 * In encoding a [SerializedLambda], this codec checks if the lambda parameter types are allowed in the configuration cache.
 * If some of them are not, it logs a problem.
 *
 * The lambda is encoded straightforwardly as a bean, and, upon decoding, the bean is expected to be the [SerializedLambda].
 * Beside the compliance checks, the values are encoded or decoded as beans without any special handling.
 *
 * Dispatches through [WideningCodec] registrations to determine which parameter types
 * cannot survive a configuration cache roundtrip — keeping the codec interface as the
 * single source of truth for unsupported value-type semantics.
 */
object SerializedLambdaParametersCheckingCodec : Codec<SerializedLambda> {
    override suspend fun ReadContext.decode(): SerializedLambda {
        return decodeBean() as SerializedLambda
    }

    override suspend fun WriteContext.encode(value: SerializedLambda) {
        checkLambdaCapturedArgTypesAreSupported(value)
        encodeBean(value)
    }

    private
    fun WriteContext.checkLambdaCapturedArgTypesAreSupported(value: SerializedLambda) {
        val signature = value.implMethodSignature
        val paramTypes: Array<Type> = getArgumentTypes(signature)

        // Treat all parameters equally, regardless of whether they are implicit captured parameters or the lambda signature ones.
        // If any of them is of an unsupported type, a build that runs from the serialized state won't be able to provide an instance anyway.
        paramTypes.forEach { paramType ->
            unsupportedNarrowedTypeFor(paramType)?.let { unsupportedKClass ->
                logUnsupportedLambdaParameterType(unsupportedKClass)
            }
        }
    }

    /**
     * Returns the parameter type as a [KClass] when its registered codec is a
     * widening codec whose decoded type cannot be assigned back to that
     * parameter type — meaning the lambda invocation post-deserialization would
     * receive a value of the wrong type. Returns null when the parameter is a
     * primitive, unloadable, has no codec, or roundtrips compatibly.
     *
     * Unlike the bean and record checks, this does not carve out the
     * "declared type is a subtype of decoded type" case. Lambda invocation
     * has no runtime type-assignment fallback: if the codec produces the
     * supertype where the lambda body expects the subtype, the call site
     * fails with a `ClassCastException` that is much harder to diagnose than
     * a store-time rejection.
     */
    private
    fun WriteContext.unsupportedNarrowedTypeFor(paramType: Type): KClass<*>? {
        if (paramType.sort != Type.OBJECT) return null
        val paramClass = try {
            Class.forName(paramType.className, false, this.javaClass.classLoader)
        } catch (_: ClassNotFoundException) {
            return null
        }
        findCodecThatWidensIncompatibly(paramClass) ?: return null
        return paramClass.kotlin
    }

    private
    fun IsolateContext.logUnsupportedLambdaParameterType(
        baseType: KClass<*>
    ) {
        logUnsupported(
            "serialize",
            // TODO: maybe introduce a separate section for the lambda serialization contract
            DocumentationSection.RequirementsDisallowedTypes
        ) {
            text(" a lambda that captures or accepts a parameter of type ")
            reference(baseType)
        }
    }
}
